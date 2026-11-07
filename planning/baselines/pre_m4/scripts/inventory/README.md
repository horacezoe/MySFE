# InventoryService integration

`inventory_service.gd` is a pure data service. It neither reads nor writes files and has no scene-node ownership. Instantiate with `preload(...).new()`. The service accepts the complete profile dictionary and preserves unrelated profile fields.

## State and definitions

- `items`: dictionary keyed by `instance_id`. Each record has `instance_id`, `definition_id`, integer `quantity`, optional `durability`, `runtime`, and additional instance metadata such as `bound`.
- `containers`: dictionary keyed by stable container IDs. Each contains `kind`, monotonically increasing integer `revision`, and `placements`. A placement is the sole ownership record for its item.
- `next_item_seq`: monotonic sequence for generated item IDs.
- `processed_commands`: `{order: Array, results: Dictionary}` holding at most the latest 256 successful commands.

`new_state()` creates `stash_main` (10×12), `loadout_pack` (6×5, 25 kg), `loadout_equipment` (weapon/helmet/vest slots), and `overflow` (unbounded list). `make_grid`, `make_slots`, and `make_list` construct additional empty containers. Remove a container only after transferring or intentionally removing all its owned instances.

`ItemDefinition` Resource fields are `id: StringName`, `display_name: String`, `category: StringName`, `width: int`, `height: int`, `unit_weight: float`, `max_stack: int`, `value: int`, `equipment_slot: StringName`, and `color: Color`. `footprint(rotated)` returns `Vector2i`. `ItemCatalog.get_definition(String)` returns a shared Resource or null; do not put mutable runtime state on that Resource. `CONTENT_VERSION` is `phase4_items_1`.

## Candidate transactions

`preview_transfer(state, command)` requires `command_id`, `item_id`, `quantity`, `from`, `to`, `source_revision`, and `target_revision`. Optional placement fields are `x: -1`, `y: -1`, `rotated: false`, and `slot: ""`. Both coordinates set to -1 request automatic placement, which first fills compatible stacks, then searches row by row and tries rotation if required. Explicit coordinates are strict. Same-container transfers support moving, rotating, and splitting, and increment the container revision once.

On success, the result contains `ok`, `reason`, `quantity`, `item_ids`, and a deep-copied `candidate`. The original dictionary is unchanged. Persist the candidate successfully before publishing it. On failure there is no candidate to publish.

`preview_take_all(state, command)` uses the same container/revision fields. Optional `item_ids: Array` restricts the batch to revealed items. It follows persisted source placement order and transfers the largest quantity that fits, including partial stacks. It reports `moved_item_ids`, `remaining_item_ids`, and total transferred `quantity`. Source IDs in that report describe the original batch; a merged source instance may no longer exist afterward. Unselected items stay untouched and are omitted from the batch report.

`preview_sort(state, container_id, command_id = "", expected_revision = -1)` repacks one grid without changing item identities, counts, or metadata. `consume(state, container_id, definition_id, amount)` returns a candidate after consuming across stacks in placement order. Consumption is for synchronized gameplay state; callers must not apply the same gameplay event twice.

`add_item(state, definition_id, amount, container_id, extra = {})` is an initialization helper. It atomically mutates `state` only on success, fills compatible stacks, and splits quantities exceeding a stack limit. It returns affected `item_ids`. Metadata differences (including `bound`, durability, or runtime) prevent merging.

## Replay and validation

Replay the exact command dictionary, including its original revisions. A cached duplicate returns success with `reason: already_applied` and the current state as its candidate; the mutation and revisions are not repeated. Reusing a command ID with different content returns `command_conflict`.

Container revisions must never reset while their IDs are reused. A transaction evicted from the bounded ledger remains rejected by stale source/target revisions. When a raid container is renamed back to a loadout container, preserve or increase its revision. Newly generated loot containers may reuse names only when old instance IDs cannot reappear in them.

`validate(state)` rejects unknown definitions, invalid quantities, orphan instances, duplicate ownership, overlaps, out-of-bounds rectangles, invalid slots, and excess weight. It does not delete or quarantine unknown items; migration owns that decision. JSON numeric values representing whole numbers are accepted. `contents(state, id)` returns cloned display records with `placement`, `definition`, `name`, `value`, `total_value`, and `weight`; these display records contain Resource references and must not be written back into the profile.

Run `--headless --path ember-3d --script res://tests/test_inventory.gd` to exercise the pure inventory invariants and transaction failure behavior. Use a separate test log path and avoid personal profile directories.
