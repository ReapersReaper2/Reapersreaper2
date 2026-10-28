# Opening bridge rendering and title transition fixes

Candidate based on `a3baef209b38a5bde46e7fc56d13b4df11ef6813` (PR #79). No merge authorization.

The Windows capture at `c1b0da34` reported a title-input exception plus eleven invalid-polygon errors. The broken parapet caps moved only their upper three vertices down by 10 pixels, crossing the lower edge. Godot 4.3 triangulates intact caps into four triangles but returns no triangles for the damaged outline. The authored random seeds place exactly eleven damaged posts.

The fix lowers all six cap vertices together. Intact geometry, seeds, colors, collision, room layout, painted textures and character artwork are unchanged. The title consumes `ui_accept` before `activate_selected()`, because New Game or Continue may remove it immediately from the scene tree.

`opening_render_regression_test.gd` validates cap triangulation at both rail heights and multiple positions, all seeded posts, fallback flagstones, and event consumption before a simulated synchronous title removal. Before the fix (with only the cap extraction refactor): 213 checks, 36 failures plus the original null-viewport exception. After: 213 checks, zero failures, clean Godot 4.3 output.

The unchanged Windows workflow discovers this test automatically and runs the same 27-frame title-to-bridge input/capture scenario as the baseline. Final Windows results and before/after screenshots are linked in the candidate PR. Existing unrelated diagnostic failures are not suppressed.
