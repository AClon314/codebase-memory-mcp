import { c } from './c';

export function apply(fn: () => string): string {
  return fn();
}

export const arrow = (): string => c();

export function viaApply(): string {
  return apply(arrow);
}

export function viaCallback(): string {
  return apply(() => c());
}
