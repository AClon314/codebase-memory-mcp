import { BaseRepo } from './base';
import type { User } from './types';

export class UserRepo extends BaseRepo<User> {
  protected load(id: string): User {
    return this.make(id);
  }

  make(id: string): User {
    return { id, name: 'u' + id };
  }
}
