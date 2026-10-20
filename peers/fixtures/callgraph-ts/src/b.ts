import { c } from './c';

export function b(): string {
  return c();
}

export function b2(): string {
  const local = () => c();
  return local();
}
