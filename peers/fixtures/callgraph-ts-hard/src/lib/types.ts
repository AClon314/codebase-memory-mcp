export interface Repo<T> {
  get(id: string): T;
  save(item: T): void;
}

export interface User {
  id: string;
  name: string;
}
