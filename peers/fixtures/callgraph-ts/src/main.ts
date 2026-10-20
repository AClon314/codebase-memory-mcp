import { b, b2 } from './b';
import { cAlias } from './c';
import { Svc, runSvc } from './svc';
import { viaApply, viaCallback } from './hof';
import { dispatch, computed, unresolved } from './dyn';

export function run(): string[] {
  const svc = new Svc();
  dispatch({ handle: () => b() });
  computed({ k: () => b2() }, 'k');
  unresolved();
  return [b(), b2(), cAlias(), svc.go(), runSvc(svc), viaApply(), viaCallback()];
}
