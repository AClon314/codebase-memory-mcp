import { c } from './c';

export interface Runner {
  go(): string;
}

export class Base {
  go(): string {
    return this.helper();
  }

  helper(): string {
    return 'base';
  }
}

export class Svc extends Base implements Runner {
  override helper(): string {
    return c();
  }
}

export function runSvc(r: Runner): string {
  return r.go();
}
