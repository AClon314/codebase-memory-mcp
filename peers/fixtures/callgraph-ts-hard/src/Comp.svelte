<script lang="ts">
  import { UserRepo } from './lib/user-repo';
  import type { User } from './lib/types';
  import { helper } from './helper';

  export let user: User;

  const repo = new UserRepo();

  function go(): string {
    const u = repo.get(user.id);
    return helper() + u.name;
  }

  $: name = go();
</script>

<div>{name}</div>
