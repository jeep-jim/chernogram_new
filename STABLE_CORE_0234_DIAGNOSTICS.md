# Chernogram 0.23.4 stable core diagnostics

Outcome: failure
Time: 2026-07-31T07:26:16Z

```text
Traceback (most recent call last):
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/materialize_stable_core_0234.py", line 886, in <module>
    main()
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/materialize_stable_core_0234.py", line 881, in main
    patch_product_ui()
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/materialize_stable_core_0234.py", line 679, in patch_product_ui
    source = replace_once(
             ^^^^^^^^^^^^^
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/materialize_stable_core_0234.py", line 38, in replace_once
    raise RuntimeError(f"{label}: expected one anchor, found {count}")
RuntimeError: product imports: expected one anchor, found 0
```
