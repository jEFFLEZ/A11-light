export const A11Config = {
  // Prefer explicit VITE_A11_API_BASE_URL (full URL in prod), fallback to local SPA proxy
  apiBaseUrl: (import.meta.env.VITE_A11_API_BASE_URL as string) || (import.meta.env.VITE_API_BASE as string) || '/api'
};
