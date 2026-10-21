<script lang="ts">
  import { b } from './b';
  export let n = 0;
  function local(): string {
    return b();
  }
  $: value = local();
</script>

<div>{value}{n}</div>
