package org.roojs.argus;

import org.gtk.android.RuntimeApplication;

public class ArgusApplication extends RuntimeApplication {
	@Override
	public void onCreate() {
		super.onCreate();
		PairBrowse.bindLibrary(this, "argus-agent");
	}
}
