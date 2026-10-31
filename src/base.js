// Where the app is served from. "/" for dev and the desktop install; "/Sizzle_FX/" on
// GitHub Pages (set by SFX_BASE at build time). Always ends with "/".
export const BASE = import.meta.env.BASE_URL;

// The GitHub Pages build (VITE_HOSTED=1): no local Python server, so the project library
// and server rendering are off and saving falls back to .json export.
export const HOSTED = import.meta.env.VITE_HOSTED === "1";

export const REPO_URL = "https://github.com/hughesdo/Sizzle_FX";
