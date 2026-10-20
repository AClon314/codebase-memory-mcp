import type { Repo } from './types';

export abstract class BaseRepo<T> implements Repo<T> {
  protected cache = new Map<string, T>();

  get(id: string): T {
    return this.load(id);
  }

  save(item: T): void {
    this.cache.set((item as { id: string }).id, item);
  }

  protected abstract load(id: string): T;
}
