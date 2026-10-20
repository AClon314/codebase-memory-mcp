export interface Handler {
  handle(): void;
}

export function dispatch(h: Handler): void {
  h.handle();
}

export function computed(obj: Record<string, () => void>, key: string): void {
  obj[key]();
}

export function unresolved(): void {
  // deliberate boundary: not defined in this repo
  (globalThis as any).__external_hook__();
}
