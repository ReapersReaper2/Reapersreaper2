package org.reapersreaper.dq005;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import androidx.core.content.FileProvider;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

public class DQ005SharePlugin extends GodotPlugin {
    public DQ005SharePlugin(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "DQ005Share"; }

    @UsedByGodot
    public boolean shareTrace(String fullTrace) {
        final Activity activity = getActivity();
        if (activity == null || fullTrace == null || fullTrace.length() == 0) return false;
        try {
            File dir = new File(activity.getCacheDir(), "dq005");
            if (!dir.exists() && !dir.mkdirs()) return false;
            File file = new File(dir, "dq005-trace.txt");
            try (FileOutputStream output = new FileOutputStream(file, false)) {
                output.write(fullTrace.getBytes(StandardCharsets.UTF_8));
                output.getFD().sync();
            }
            Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", file);
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType("text/plain");
            send.putExtra(Intent.EXTRA_STREAM, uri);
            send.putExtra(Intent.EXTRA_SUBJECT, "DQ005 diagnostic trace");
            send.setClipData(android.content.ClipData.newRawUri("dq005-trace.txt", uri));
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            activity.runOnUiThread(() -> activity.startActivity(Intent.createChooser(send, "Export DQ005 trace")));
            return true;
        } catch (Exception ex) {
            android.util.Log.e("DQ005Share", "file share failed", ex);
            return false;
        }
    }
}
