const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const pty = require('node-pty');
const axios = require('axios');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const app = express();
const server = http.createServer(app);
const io = new Server(server);

const PORT = Math.max(1, Math.min(Number(process.env.PORT) || 3000, 65535));
const PROXMOX_HOST_IP = String(process.env.PROXMOX_HOST_IP || '192.168.8.12').trim();
const USER_AGENT = 'Mozilla/5.0';
const DATA_DIR = path.join(__dirname, 'data');
const SETTINGS_FILE = path.join(DATA_DIR, 'settings.json');
const SSH_KEY_DIR = path.join(DATA_DIR, 'ssh');
const SSH_KEY_PATH = path.join(SSH_KEY_DIR, 'proxmox_helper_rsa');
const CURRENT_SCRIPTS_URLS = [
    'https://community-scripts.org/categories',
    'https://community-scripts.github.io/ProxmoxVE/categories',
    'https://community-scripts.org/scripts',
    'https://community-scripts.github.io/ProxmoxVE/scripts',
];
const SCRIPT_DETAIL_BASE_URL = 'https://community-scripts.org/scripts';
const RAW_SCRIPT_BASE_URL = 'https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main';
const LEGACY_SCRIPTS_JSON_URL = 'https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/json/scripts.json';
const SCRIPT_PATH_OVERRIDES = {
    netdata: 'tools/addon/netdata.sh',
    'pve-netdata': 'tools/addon/netdata.sh',
};
const SCRIPT_PATH_FALLBACKS = [
    'ct',
    'vm',
    'misc',
    'tools',
    'tools/addon',
    'tools/pve',
    'tools/pbs',
    'tools/pmg',
];
const OFFICIAL_CATEGORY_ORDER = [
    'Proxmox & Virtualization',
    'Operating Systems',
    'Containers & Docker',
    'Network & Firewall',
    'Adblock & DNS',
    'Authentication & Security',
    'Backup & Recovery',
    'Databases',
    'Monitoring & Analytics',
    'Dashboards & Frontends',
    'Files & Downloads',
    'Documents & Notes',
    'Media & Streaming',
    '*Arr Suite',
    'NVR & Cameras',
    'IoT & Smart Home',
    'ZigBee, Z-Wave & Matter',
    'MQTT & Messaging',
    'Automation & Scheduling',
    'AI / Coding & Dev-Tools',
    'Webservers & Proxies',
    'Bots & ChatOps',
    'Finance & Budgeting',
    'Gaming & Leisure',
    'Business & ERP',
    'Miscellaneous',
];

const DEFAULT_SETTINGS = {
    hosts: [
        {
            id: 'default',
            name: 'Proxmox',
            address: PROXMOX_HOST_IP,
            port: 22,
            user: 'root',
            authType: 'app-key',
            password: '',
            privateKeyPath: '',
            passphrase: '',
            hostKeyMode: 'accept-new',
            sessionMode: 'normal',
        },
    ],
    sshKey: null,
};

app.use((req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
});

app.use(express.json({ limit: '1mb' }));
app.use(express.static(path.join(__dirname, 'public')));

app.get(['/categories', '/scripts', '/scripts/:slug'], (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

function ensureDataDirs() {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.mkdirSync(SSH_KEY_DIR, { recursive: true });
}

function hostId(value) {
    return slugify(value || `host-${Date.now()}`) || `host-${Date.now()}`;
}

function normalizeHost(host, index = 0) {
    const name = String(host?.name || `Proxmox ${index + 1}`).trim();
    const address = String(host?.address || host?.host || '').trim();
    const user = String(host?.user || 'root').trim();
    const port = Math.max(1, Math.min(Number(host?.port) || 22, 65535));
    const id = hostId(host?.id || name || address || `host-${index + 1}`);
    const authType = ['app-key', 'password', 'private-key'].includes(String(host?.authType || '').trim())
        ? String(host.authType).trim()
        : 'app-key';
    const hostKeyMode = ['accept-new', 'ask', 'off'].includes(String(host?.hostKeyMode || '').trim())
        ? String(host.hostKeyMode).trim()
        : 'accept-new';
    const sessionMode = ['normal', 'persistent'].includes(String(host?.sessionMode || '').trim())
        ? String(host.sessionMode).trim()
        : 'normal';

    return {
        id,
        name,
        address,
        port,
        user,
        authType,
        password: String(host?.password || ''),
        privateKeyPath: String(host?.privateKeyPath || ''),
        passphrase: String(host?.passphrase || ''),
        hostKeyMode,
        sessionMode,
    };
}

function normalizeSettings(settings) {
    const hosts = (Array.isArray(settings?.hosts) ? settings.hosts : DEFAULT_SETTINGS.hosts)
        .map(normalizeHost)
        .filter(host => host.address);

    return {
        hosts: hosts.length ? hosts.slice(0, 4) : DEFAULT_SETTINGS.hosts,
        sshKey: settings?.sshKey || null,
    };
}

function readSettings() {
    ensureDataDirs();

    try {
        if (!fs.existsSync(SETTINGS_FILE)) {
            writeSettings(DEFAULT_SETTINGS);
            return normalizeSettings(DEFAULT_SETTINGS);
        }

        return normalizeSettings(JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8')));
    } catch (_err) {
        return normalizeSettings(DEFAULT_SETTINGS);
    }
}

function writeSettings(settings) {
    ensureDataDirs();
    const normalized = normalizeSettings(settings);
    fs.writeFileSync(SETTINGS_FILE, `${JSON.stringify(normalized, null, 2)}\n`);
    return normalized;
}

function b64urlToBuffer(value) {
    const base64 = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
    return Buffer.from(base64.padEnd(Math.ceil(base64.length / 4) * 4, '='), 'base64');
}

function sshString(value) {
    const buffer = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
    const length = Buffer.alloc(4);
    length.writeUInt32BE(buffer.length, 0);
    return Buffer.concat([length, buffer]);
}

function sshMpint(buffer) {
    let value = Buffer.from(buffer);
    while (value.length > 1 && value[0] === 0) value = value.slice(1);
    if (value[0] & 0x80) value = Buffer.concat([Buffer.from([0]), value]);
    return sshString(value);
}

function rsaPublicKeyToOpenSsh(publicKey) {
    const jwk = publicKey.export({ format: 'jwk' });
    const keyType = 'ssh-rsa';
    const blob = Buffer.concat([
        sshString(keyType),
        sshMpint(b64urlToBuffer(jwk.e)),
        sshMpint(b64urlToBuffer(jwk.n)),
    ]);

    return {
        publicKey: `${keyType} ${blob.toString('base64')} proxmox-helper-local`,
        fingerprint: `SHA256:${crypto.createHash('sha256').update(blob).digest('base64').replace(/=+$/, '')}`,
    };
}

function generateSshKeyPair() {
    ensureDataDirs();
    const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
        modulusLength: 3072,
        publicExponent: 0x10001,
    });
    const privatePem = privateKey.export({ type: 'pkcs1', format: 'pem' });
    const openSsh = rsaPublicKeyToOpenSsh(publicKey);

    fs.writeFileSync(SSH_KEY_PATH, privatePem, { mode: 0o600 });
    fs.writeFileSync(`${SSH_KEY_PATH}.pub`, `${openSsh.publicKey}\n`);

    const settings = readSettings();
    return writeSettings({
        ...settings,
        sshKey: {
            publicKey: openSsh.publicKey,
            fingerprint: openSsh.fingerprint,
            privateKeyPath: SSH_KEY_PATH,
            createdAt: new Date().toISOString(),
        },
    });
}

function deployHostForRequest(script) {
    const settings = readSettings();
    const hosts = settings.hosts || [];
    const requestedHostId = script?.hostId || script?.proxmoxHostId;
    const host = requestedHostId
        ? hosts.find(item => item.id === requestedHostId)
        : hosts[0];

    if (!host) {
        throw new Error('No Proxmox host is configured. Open Settings and add a host.');
    }

    return { host, settings };
}

function parseFlightStrings(html) {
    const strings = [];
    const re = /self\.__next_f\.push\(\[1,"([\s\S]*?)"\]\)<\/script>/g;
    let match;

    while ((match = re.exec(html)) !== null) {
        try {
            strings.push(JSON.parse(`"${match[1]}"`));
        } catch (_err) {
            // Ignore chunks that are not simple string payloads.
        }
    }

    return strings.join('');
}

function normalizeFlightReferenceId(id) {
    return String(id || '').replace(/^0+/, '') || '0';
}

function extractFlightTextReferences(flight) {
    const references = new Map();
    const re = /([0-9a-f]+):T([0-9a-f]+),/gi;
    let match;

    while ((match = re.exec(flight)) !== null) {
        const length = parseInt(match[2], 16);
        if (!Number.isFinite(length)) continue;

        const valueStart = match.index + match[0].length;
        const value = flight.slice(valueStart, valueStart + length);
        references.set(match[1], value);
        references.set(normalizeFlightReferenceId(match[1]), value);
        re.lastIndex = valueStart + length;
    }

    return references;
}

function resolveFlightReference(value, references) {
    if (typeof value !== 'string') return value || '';
    const match = value.match(/^\$([0-9a-f]+)$/i);
    if (!match) return value;
    return references.get(match[1]) || references.get(normalizeFlightReferenceId(match[1])) || '';
}

function extractJsonValue(text, valueStart) {
    const stack = [];
    let inString = false;
    let escaped = false;

    for (let i = valueStart; i < text.length; i++) {
        const ch = text[i];

        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch === '\\') {
                escaped = true;
            } else if (ch === '"') {
                inString = false;
            }
            continue;
        }

        if (ch === '"') {
            inString = true;
        } else if (ch === '{') {
            stack.push('}');
        } else if (ch === '[') {
            stack.push(']');
        } else if ((ch === '}' || ch === ']') && stack.pop() !== ch) {
            throw new Error('Malformed scripts payload');
        }

        if (stack.length === 0 && i > valueStart) {
            return text.slice(valueStart, i + 1);
        }
    }

    throw new Error('Scripts payload was not complete');
}

function extractInitData(html) {
    const flight = parseFlightStrings(html);
    const marker = '"initData":';
    const markerIndex = flight.indexOf(marker);

    if (markerIndex === -1) {
        throw new Error('Could not find initData in scripts page');
    }

    const valueStart = flight.indexOf('{', markerIndex + marker.length);
    if (valueStart === -1) {
        throw new Error('Could not find initData object');
    }

    return JSON.parse(extractJsonValue(flight, valueStart));
}

function extractScriptData(html) {
    const flight = parseFlightStrings(html);
    const textReferences = extractFlightTextReferences(flight);
    const marker = '"scriptData":';
    const markerIndex = flight.indexOf(marker);

    if (markerIndex === -1) {
        throw new Error('Could not find scriptData in script page');
    }

    const valueStart = flight.indexOf('{', markerIndex + marker.length);
    if (valueStart === -1) {
        throw new Error('Could not find scriptData object');
    }

    const scriptData = JSON.parse(extractJsonValue(flight, valueStart));
    if (Array.isArray(scriptData.releases)) {
        scriptData.releases = scriptData.releases.map(release => ({
            ...release,
            body: resolveFlightReference(release.body, textReferences),
        }));
    }

    return scriptData;
}

function cleanText(value) {
    return String(value || '')
        .replace(/<\/p>\s*<p[^>]*>/gi, '\n\n')
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/?(p|strong|em|b|i|ul|ol|li|a|code|pre|span|div|h[1-6])\b[^>]*>/gi, '')
        .replace(/&nbsp;/gi, ' ')
        .replace(/&amp;/gi, '&')
        .replace(/&lt;/gi, '<')
        .replace(/&gt;/gi, '>')
        .replace(/&quot;/gi, '"')
        .replace(/&#39;/gi, "'")
        .replace(/<\/p>\s*<p[^>]*>/gi, '\n\n')
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/?(p|strong|em|b|i|ul|ol|li|a|code|pre|span|div|h[1-6])\b[^>]*>/gi, '')
        .replace(/[ \t]+\n/g, '\n')
        .replace(/\n{3,}/g, '\n\n')
        .trim();
}

function normalizeNotes(notes) {
    return Array.isArray(notes)
        ? notes.map(note => ({ ...note, text: cleanText(note.text) })).filter(note => note.text)
        : [];
}

function typeName(script) {
    return String(script?.expand?.type?.type || script?.type || '').toLowerCase();
}

function sourceUrlForPath(scriptPath) {
    return `${RAW_SCRIPT_BASE_URL}/${scriptPath.replace(/^\/+/, '')}`;
}

function githubUrlForPath(scriptPath) {
    return `https://github.com/community-scripts/ProxmoxVE/blob/main/${scriptPath.replace(/^\/+/, '')}`;
}

function installCommandForPath(scriptPath) {
    return `bash -c "$(curl -fsSL ${sourceUrlForPath(scriptPath)})"`;
}

function parseRawScriptPath(value) {
    const text = String(value || '');
    const rawMatch = text.match(/raw\.githubusercontent\.com\/community-scripts\/ProxmoxVE\/main\/([^"'\s)]+)/i);
    if (rawMatch) return rawMatch[1];

    const githubMatch = text.match(/github\.com\/community-scripts\/ProxmoxVE\/blob\/main\/([^"'\s)]+)/i);
    return githubMatch ? githubMatch[1] : '';
}

function preferredScriptPath(script, slug) {
    if (SCRIPT_PATH_OVERRIDES[slug]) return SCRIPT_PATH_OVERRIDES[slug];

    const explicitPath = script?.sourcePath || script?.script_path || script?.scriptPath || script?.file_path || script?.path;
    if (explicitPath) return String(explicitPath).replace(/^\/+/, '');

    const rawPath = parseRawScriptPath(script?.rawScriptUrl || script?.installCommand || script?.sourceUrl || script?.scriptUrl || '');
    if (rawPath) return rawPath;

    const kind = typeName(script);
    if (kind.includes('vm') || slug.endsWith('-vm')) return `vm/${slug}.sh`;
    if (kind.includes('lxc') || kind.includes('ct')) return `ct/${slug}.sh`;
    return `ct/${slug}.sh`;
}

function scriptPathCandidates(script, slug) {
    const preferred = preferredScriptPath(script, slug);
    const candidates = [
        preferred,
        ...SCRIPT_PATH_FALLBACKS.map(folder => `${folder}/${slug}.sh`),
    ];

    return [...new Set(candidates.filter(Boolean).map(candidate => candidate.replace(/^\/+/, '')))];
}

async function resolveDeployScript(script, slug) {
    if (SCRIPT_PATH_OVERRIDES[slug]) {
        const scriptPath = SCRIPT_PATH_OVERRIDES[slug];
        return { scriptPath, scriptUrl: sourceUrlForPath(scriptPath) };
    }

    for (const scriptPath of scriptPathCandidates(script, slug)) {
        const scriptUrl = sourceUrlForPath(scriptPath);

        try {
            const response = await axios.head(scriptUrl, {
                headers: { 'User-Agent': USER_AGENT },
                validateStatus: () => true,
            });

            if (response.status >= 200 && response.status < 300) {
                return { scriptPath, scriptUrl };
            }
        } catch (_err) {
            // Try the next official path candidate.
        }
    }

    throw new Error(`Could not find ${slug}.sh in the official script folders`);
}

function shellQuote(value) {
    return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function stripAnsi(value) {
    return String(value || '').replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '');
}

function isDeploySuccessText(value) {
    const text = String(value || '').trim();
    if (!text) return false;

    return /\bcompleted successfully!?/i.test(text)
        || /\bdeploy(?:ment)? successful!?/i.test(text)
        || /\binstallation successful!?/i.test(text);
}

function expandHomePath(value) {
    let text = String(value || '').trim();
    if (!text) return '';

    if ((text.startsWith('~/') || text.startsWith('~\\')) && (process.env.USERPROFILE || process.env.HOME)) {
        text = path.join(process.env.USERPROFILE || process.env.HOME, text.slice(2));
    }

    return path.isAbsolute(text) ? text : path.resolve(text);
}

function sshAuthLabel(host) {
    if (host?.authType === 'password') return 'saved password';
    if (host?.authType === 'private-key') return 'custom private key';
    return 'generated app key';
}

function sshSessionLabel(host) {
    return host?.sessionMode === 'persistent' ? 'persistent reconnect mode' : 'normal SSH mode';
}

function tmuxSessionName(script, slug) {
    const rawName = script?.sessionName || `pve-${slug}`;
    const safeName = String(rawName)
        .toLowerCase()
        .replace(/[^a-z0-9_-]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 80);

    return safeName || `pve-${slug}`;
}

function remoteScriptRunner(scriptUrl) {
    return [
        `script_content="$(curl -fsSL ${shellQuote(scriptUrl)})"`,
        `curl_code=$?`,
        `if [ "$curl_code" -ne 0 ]; then echo "[Deploy] Failed to download script: ${scriptUrl}"; exit "$curl_code"; fi`,
        `bash -c "$script_content"`,
    ].join('; ');
}

function buildRemoteTmuxCommand({ cols, rows, scriptPath, scriptUrl, sessionName }) {
    const runner = [
        `stty cols ${cols} rows ${rows} 2>/dev/null || true`,
        `clear`,
        `echo "[Deploy] Running ${scriptPath}"`,
        remoteScriptRunner(scriptUrl),
        `exit_code=$?`,
        `echo`,
        `echo "[Deploy] Script exited with code $exit_code"`,
        `echo "[Deploy] This tmux session stays open so the web UI can reconnect."`,
        `echo "[Deploy] Type exit here when you are finished with the log."`,
        `exec bash`,
    ].join('; ');
    const quotedSession = shellQuote(sessionName);

    return [
        `stty cols ${cols} rows ${rows} 2>/dev/null || true`,
        `if ! command -v tmux >/dev/null 2>&1; then echo '[Persistent mode] tmux is not installed on this host.'; echo '[Guide] Install tmux on the remote host, then deploy again.'; if command -v apt-get >/dev/null 2>&1; then echo '[Guide] sudo apt update && sudo apt install -y tmux'; elif command -v dnf >/dev/null 2>&1; then echo '[Guide] sudo dnf install -y tmux'; elif command -v yum >/dev/null 2>&1; then echo '[Guide] sudo yum install -y tmux'; elif command -v apk >/dev/null 2>&1; then echo '[Guide] sudo apk add tmux'; else echo '[Guide] Install the tmux package with your host package manager.'; fi; exit 127; fi`,
        `if tmux has-session -t ${quotedSession} 2>/dev/null; then echo '[tmux] Reattaching to existing deploy session ${sessionName}'; else echo '[tmux] Starting deploy session ${sessionName}'; tmux new-session -d -s ${quotedSession}; tmux send-keys -t ${quotedSession} ${shellQuote(runner)} C-m; fi`,
        `tmux resize-window -t ${quotedSession} -x ${cols} -y ${rows} 2>/dev/null || true`,
        `tmux attach-session -t ${quotedSession}`,
    ].join('; ');
}

function normalizeScript(script) {
    const slug = script.slug || slugify(script.name || '');
    const scriptPath = preferredScriptPath(script, slug);

    return {
        name: script.name,
        slug,
        description: cleanText(script.description),
        logo: script.logo,
        type: script.expand?.type?.type || script.type,
        privileged: Boolean(script.privileged),
        is_dev: Boolean(script.is_dev),
        is_disabled: Boolean(script.is_disabled),
        is_deleted: Boolean(script.is_deleted),
        disable_message: script.disable_message || '',
        deleted_message: script.deleted_message || '',
        has_arm: Boolean(script.has_arm),
        notes: normalizeNotes(script.notes),
        install_methods: Array.isArray(script.install_methods) ? script.install_methods : [],
        port: script.port || '',
        config_path: script.config_path || '',
        default_user: script.default_user || '',
        default_passwd: script.default_passwd || '',
        documentation: script.documentation || '',
        website: script.website || '',
        github: script.github || '',
        github_url: script.github ? `https://github.com/${script.github}` : '',
        execute_in: Array.isArray(script.execute_in) ? script.execute_in : [],
        updateable: Boolean(script.updateable),
        script_created: script.script_created || '',
        script_updated: script.script_updated || '',
        updated: script.updated || '',
        last_update_commit: script.last_update_commit || '',
        officialUrl: slug ? `${SCRIPT_DETAIL_BASE_URL}/${slug}` : '',
        sourcePath: scriptPath,
        sourceUrl: slug ? githubUrlForPath(scriptPath) : '',
        rawScriptUrl: slug ? sourceUrlForPath(scriptPath) : '',
        installCommand: slug ? installCommandForPath(scriptPath) : '',
    };
}

function isVisibleOfficialScript(script) {
    return !script?.is_disabled
        && !script?.is_deleted
        && !script?.disable_message
        && !script?.deleted_message;
}

function normalizeCategoryName(category, categoryById) {
    if (!category) return null;
    if (typeof category === 'string') return categoryById.get(category)?.name || category;
    return category.name || category.title || category.id || null;
}

function normalizeScriptDetail(scriptData, requestedSlug) {
    const script = scriptData?.script || {};
    const slug = slugify(script.slug || requestedSlug || script.name || '');
    const scriptPath = preferredScriptPath(script, slug);
    const categories = (script.expand?.categories || script.categories || [])
        .map(category => normalizeCategoryName(category, new Map()))
        .filter(Boolean);
    const releases = Array.isArray(scriptData?.releases) ? scriptData.releases : [];
    const installMethods = Array.isArray(script.install_methods) ? script.install_methods : [];

    return {
        ...normalizeScript(script),
        slug,
        officialUrl: `${SCRIPT_DETAIL_BASE_URL}/${slug}`,
        sourcePath: scriptPath,
        sourceUrl: githubUrlForPath(scriptPath),
        rawScriptUrl: sourceUrlForPath(scriptPath),
        installCommand: installCommandForPath(scriptPath),
        categories,
        notes: normalizeNotes(script.notes),
        install_methods: installMethods,
        releases: releases.slice(0, 5).map(release => ({
            name: release.name || release.tag_name || '',
            tag_name: release.tag_name || '',
            published_at: release.published_at || '',
            body: /^\$\d+$/.test(String(release.body || '')) ? '' : release.body || '',
            html_url: release.html_url || '',
        })),
        port: script.port || '',
        config_path: script.config_path || '',
        default_user: script.default_user || '',
        default_passwd: script.default_passwd || '',
        documentation: script.documentation || '',
        website: script.website || '',
        github: script.github || '',
        github_url: script.github ? `https://github.com/${script.github}` : '',
        execute_in: Array.isArray(script.execute_in) ? script.execute_in : [],
        updateable: Boolean(script.updateable),
        script_created: script.script_created || '',
        script_updated: script.script_updated || '',
        updated: script.updated || '',
        last_update_commit: script.last_update_commit || '',
    };
}

function addScriptToCategory(grouped, categoryName, script) {
    if (!grouped[categoryName]) grouped[categoryName] = [];
    if (!grouped[categoryName].some(existing => (existing.slug || existing.name) === (script.slug || script.name))) {
        grouped[categoryName].push(script);
    }
}

function orderGroupedCategories(grouped, orderedCategoryNames = OFFICIAL_CATEGORY_ORDER) {
    const ordered = {};

    orderedCategoryNames.forEach(categoryName => {
        if (grouped[categoryName]?.length) {
            ordered[categoryName] = grouped[categoryName];
        }
    });

    Object.entries(grouped).forEach(([categoryName, scripts]) => {
        if (!ordered[categoryName] && scripts.length) {
            ordered[categoryName] = scripts;
        }
    });

    return ordered;
}

function groupScripts(payload) {
    if (payload && !Array.isArray(payload) && !payload.scripts && Object.values(payload).every(Array.isArray)) {
        const filtered = Object.fromEntries(
            Object.entries(payload).map(([categoryName, scripts]) => [
                categoryName,
                scripts.filter(isVisibleOfficialScript),
            ])
        );

        return orderGroupedCategories(filtered, Object.keys(payload));
    }

    const categoryList = payload?.categories || [];
    const scripts = Array.isArray(payload) ? payload : payload?.scripts || payload?.items || [];
    const categoryById = new Map(categoryList.map(category => [category.id, category]));
    const officialCategoryNames = categoryList.length
        ? categoryList
            .slice()
            .sort((a, b) => (a.sort_order || 0) - (b.sort_order || 0))
            .map(category => category.name)
        : OFFICIAL_CATEGORY_ORDER;
    const grouped = {};

    officialCategoryNames.forEach(categoryName => {
        grouped[categoryName] = [];
    });

    scripts.forEach(script => {
        if (!isVisibleOfficialScript(script)) return;

        const categories = script.expand?.categories?.length ? script.expand.categories : script.categories || script.category;
        const rawCategories = Array.isArray(categories) ? categories : categories ? [categories] : [];

        const categoryNames = rawCategories
            .map(category => normalizeCategoryName(category, categoryById))
            .filter(categoryName => categoryName && (categoryList.length === 0 || officialCategoryNames.includes(categoryName)));

        const normalizedScript = {
            ...normalizeScript(script),
            categories: categoryNames.length ? categoryNames : ['Miscellaneous'],
        };
        normalizedScript.categories.forEach(categoryName => addScriptToCategory(grouped, categoryName, normalizedScript));
    });

    return orderGroupedCategories(Object.fromEntries(
        Object.entries(grouped).filter(([, scripts]) => scripts.length > 0)
    ), officialCategoryNames);
}

function slugify(value) {
    return String(value)
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');
}

app.get('/api/scripts', async (req, res) => {
    let currentSourceError;

    for (const scriptsUrl of CURRENT_SCRIPTS_URLS) {
        try {
            const response = await axios.get(scriptsUrl, {
                headers: { 'User-Agent': USER_AGENT }
            });
            return res.json(groupScripts(extractInitData(response.data)));
        } catch (err) {
            currentSourceError = currentSourceError || err;
        }
    }

    try {
        const fallback = await axios.get(LEGACY_SCRIPTS_JSON_URL, {
            headers: { 'User-Agent': USER_AGENT }
        });
        res.json(groupScripts(fallback.data));
    } catch (fallbackErr) {
        console.error(currentSourceError);
        console.error(fallbackErr);
        res.status(500).send("Failed to fetch scripts");
    }
});

app.get('/api/scripts/:slug', async (req, res) => {
    const slug = slugify(req.params.slug || '');
    if (!slug) {
        res.status(400).send('Missing script slug');
        return;
    }

    try {
        const response = await axios.get(`${SCRIPT_DETAIL_BASE_URL}/${slug}`, {
            headers: { 'User-Agent': USER_AGENT }
        });
        res.json(normalizeScriptDetail(extractScriptData(response.data), slug));
    } catch (err) {
        console.error(err);
        res.status(500).send('Failed to fetch script details');
    }
});

app.get('/api/settings', (_req, res) => {
    res.json(readSettings());
});

app.post('/api/settings', (req, res) => {
    const existing = readSettings();
    const next = writeSettings({
        ...existing,
        hosts: Array.isArray(req.body?.hosts) ? req.body.hosts : existing.hosts,
    });
    res.json(next);
});

app.post('/api/settings/ssh-key', (_req, res) => {
    res.json(generateSshKeyPair());
});

io.on('connection', (socket) => {
    let shell = null;

    socket.on('deploy', async (script) => {
        if (shell) {
            try {
                shell.kill();
            } catch (_err) {
                // The previous PTY may already be closed.
            }
            shell = null;
        }

        const rawSlug = typeof script === 'object' && script !== null ? script.slug || script.name : script;
        const slug = slugify(rawSlug || '');
        if (!slug) {
            socket.emit('output', '\r\n\x1b[31m[Error] Missing script slug\x1b[0m\r\n');
            return;
        }

        let deployTarget;
        try {
            deployTarget = deployHostForRequest(script);
        } catch (err) {
            socket.emit('output', `\r\n\x1b[31m[Error] ${err.message}\x1b[0m\r\n`);
            socket.emit('deploy-exit', { exitCode: 2 });
            return;
        }

        const { host, settings } = deployTarget;
        const cols = Math.max(80, Math.min(Number(script?.cols) || 120, 240));
        const rows = Math.max(24, Math.min(Number(script?.rows) || 36, 80));

        let resolved;
        try {
            socket.emit('output', `\r\n\x1b[36m[Deploy] Resolving official script path for ${slug}.sh\x1b[0m\r\n`);
            resolved = await resolveDeployScript(script, slug);
        } catch (err) {
            socket.emit('output', `\r\n\x1b[31m[Error] ${err.message}\x1b[0m\r\n`);
            socket.emit('deploy-exit', { exitCode: 127 });
            return;
        }

        const { scriptPath, scriptUrl } = resolved;
        const sessionName = tmuxSessionName(script, slug);
        const usePersistentSession = (host.sessionMode || script?.sessionMode) === 'persistent';
        const remoteCommand = usePersistentSession
            ? buildRemoteTmuxCommand({
                cols,
                rows,
                scriptPath,
                scriptUrl,
                sessionName,
            })
            : `stty cols ${cols} rows ${rows} 2>/dev/null || true; echo "[Deploy] Running ${scriptPath}"; ${remoteScriptRunner(scriptUrl)}`;

        const authType = host.authType || 'app-key';
        const destination = `${host.user}@${host.address}`;
        const sshArgs = [
            '-tt',
            '-o', 'ServerAliveInterval=15',
            '-o', 'ServerAliveCountMax=12',
            '-o', 'TCPKeepAlive=yes',
        ];

        if (host.hostKeyMode === 'accept-new') {
            sshArgs.push('-o', 'StrictHostKeyChecking=accept-new');
        } else if (host.hostKeyMode === 'off') {
            sshArgs.push('-o', 'StrictHostKeyChecking=no');
        }

        if (authType === 'password') {
            sshArgs.push(
                '-o', 'PreferredAuthentications=password,keyboard-interactive',
                '-o', 'PubkeyAuthentication=no',
            );
        } else if (authType === 'private-key') {
            const privateKeyPath = expandHomePath(host.privateKeyPath);
            if (!privateKeyPath || !fs.existsSync(privateKeyPath)) {
                socket.emit('output', '\r\n\x1b[31m[Error] The custom private key path for this host does not exist. Update it in Settings.\x1b[0m\r\n');
                socket.emit('deploy-exit', { exitCode: 2 });
                return;
            }

            sshArgs.push('-i', privateKeyPath, '-o', 'IdentitiesOnly=yes');
        } else {
            const generatedKeyPath = settings.sshKey?.privateKeyPath;
            if (!generatedKeyPath || !fs.existsSync(generatedKeyPath)) {
                socket.emit('output', '\r\n\x1b[31m[Error] This host is set to use the generated app SSH key, but no key exists yet. Open Settings and generate one first.\x1b[0m\r\n');
                socket.emit('deploy-exit', { exitCode: 2 });
                return;
            }

            sshArgs.push('-i', generatedKeyPath, '-o', 'IdentitiesOnly=yes');
        }

        sshArgs.push('-p', String(host.port || 22), destination, remoteCommand);

        socket.emit('output', usePersistentSession
            ? `\r\n\x1b[36m[SSH] Connecting to ${destination} using ${sshAuthLabel(host)} in ${sshSessionLabel(host)} and attaching tmux session ${sessionName}\x1b[0m\r\n`
            : `\r\n\x1b[36m[SSH] Connecting to ${destination} using ${sshAuthLabel(host)} in ${sshSessionLabel(host)} and running ${scriptPath}\x1b[0m\r\n`);

        shell = pty.spawn('ssh', sshArgs, {
            name: 'xterm-256color',
            cols,
            rows,
            env: {
                ...process.env,
                TERM: 'xterm-256color',
            },
        });

        const authPrompts = {
            passwordSent: 0,
            passphraseSent: 0,
            hostKeyAccepted: false,
            remoteStarted: false,
        };
        const successDetection = {
            emitted: false,
            buffer: '',
        };

        shell.onData(data => {
            socket.emit('output', data);
            const plainText = stripAnsi(data);
            if (plainText.includes('[Deploy] Running')) {
                authPrompts.remoteStarted = true;
            }

            successDetection.buffer += plainText.replace(/\0/g, '');
            const lines = successDetection.buffer.split(/\r\n|\n|\r/g);
            successDetection.buffer = lines.pop() || '';

            for (const line of lines) {
                if (!successDetection.emitted && isDeploySuccessText(line)) {
                    successDetection.emitted = true;
                    socket.emit('deploy-success', { line: line.trim() });
                }
            }

            if (!successDetection.emitted && isDeploySuccessText(successDetection.buffer)) {
                successDetection.emitted = true;
                socket.emit('deploy-success', { line: successDetection.buffer.trim() });
            }

            if (!authPrompts.remoteStarted && !authPrompts.hostKeyAccepted && host.hostKeyMode !== 'ask' && /continue connecting \(yes\/no(?:\/\[fingerprint\])?\)\?/i.test(plainText)) {
                authPrompts.hostKeyAccepted = true;
                shell.write('yes\r');
                socket.emit('output', '\r\n\x1b[36m[SSH] Accepting the host key for this connection.\x1b[0m\r\n');
                return;
            }

            if (!authPrompts.remoteStarted && authType === 'private-key' && host.passphrase && authPrompts.passphraseSent < 2 && /(enter passphrase for key|passphrase for)/i.test(plainText)) {
                authPrompts.passphraseSent += 1;
                shell.write(`${host.passphrase}\r`);
                return;
            }

            if (!authPrompts.remoteStarted && host.password && authPrompts.passwordSent < 2 && /(password|verification code|one-time password|otp).*:\s*$/i.test(plainText)) {
                authPrompts.passwordSent += 1;
                shell.write(`${host.password}\r`);
            }
        });
        shell.onExit(({ exitCode, signal }) => {
            if (exitCode === 0) {
                socket.emit('output', '\r\n\x1b[32m[Done]\x1b[0m\r\n');
            } else {
                socket.emit('output', `\r\n\x1b[33m[SSH session closed${exitCode !== undefined ? `, exit ${exitCode}` : ''}${signal ? `, signal ${signal}` : ''}]\x1b[0m\r\n`);
            }
            socket.emit('deploy-exit', { exitCode, signal });
            shell = null;
        });
    });

    socket.on('input', data => {
        if (typeof data !== 'string') return;
        if (!shell) return;

        try {
            shell.write(data);
        } catch (_err) {
            shell = null;
        }
    });

    socket.on('resize', size => {
        if (!shell || !size) return;

        const cols = Math.max(80, Math.min(Number(size.cols) || 120, 240));
        const rows = Math.max(24, Math.min(Number(size.rows) || 36, 80));
        try {
            shell.resize(cols, rows);
        } catch (_err) {
            shell = null;
        }
    });

    socket.on('detach', () => {
        if (!shell) return;

        try {
            shell.kill();
        } catch (_err) {
            // The SSH attachment may already be closed.
        }
        shell = null;
    });

    socket.on('disconnect', () => {
        if (shell) {
            try {
                shell.kill();
            } catch (_err) {
                // The PTY may already be closed.
            }
            shell = null;
        }
    });
});

server.listen(PORT, '0.0.0.0', () => console.log(`Server started on http://0.0.0.0:${PORT}`));
