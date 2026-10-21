import { RepoAlias } from '@lib/barrel';
import type { User } from '@lib/types';
import { helper } from './helper';

export function useAlias(): User {
  return new RepoAlias().get('1');
}

export function identity<T>(x: T): T {
  return x;
}

export function useGeneric(): User {
  return identity<User>({ id: '1', name: 'n' });
}

export async function load(): Promise<User> {
  return { id: '2', name: 'n' };
}

export type Unwrap<T> = T extends Promise<infer U> ? U : T;

export function useCond(): Promise<Unwrap<ReturnType<typeof load>>> {
  return load();
}

export function apply<T>(fn: () => T): T {
  return fn();
}

export function useHof(): string {
  return apply(() => helper());
}

export function pick(x: string): string;
export function pick(x: number): number;
export function pick(x: string | number): string | number {
  return x;
}

export function useOverload(): string {
  return pick('s');
}
