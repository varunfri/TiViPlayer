// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.MediaItem;
import androidx.media3.common.util.Log;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DataSource;
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager;
import androidx.media3.exoplayer.drm.DrmSessionManager;
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider;
import androidx.media3.exoplayer.drm.DummyExoMediaDrm;
import androidx.media3.exoplayer.drm.ExoMediaDrm;
import androidx.media3.exoplayer.drm.FrameworkMediaDrm;
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback;
import androidx.media3.exoplayer.drm.UnsupportedDrmException;
import com.google.common.primitives.Ints;
import java.util.Map;
import java.util.Objects;

/**
 * A {@link DrmSessionManagerProvider} that configures {@link DefaultDrmSessionManager} with
 * {@link WidevineL3MediaDrm} to prevent physical Android devices from failing to render DRM video
 * frames onto Flutter's {@code SurfaceTexture}.
 */
@UnstableApi
public final class WidevineL3DrmSessionManagerProvider implements DrmSessionManagerProvider {
  private static final String TAG = "WidevineL3DrmProvider";
  private final Object lock = new Object();
  private final DataSource.Factory dataSourceFactory;
  private DrmSessionManager manager;
  private MediaItem.DrmConfiguration drmConfiguration;

  public WidevineL3DrmSessionManagerProvider(@NonNull DataSource.Factory dataSourceFactory) {
    this.dataSourceFactory = dataSourceFactory;
  }

  @NonNull
  @Override
  public DrmSessionManager get(@NonNull MediaItem mediaItem) {
    if (mediaItem.localConfiguration == null
        || mediaItem.localConfiguration.drmConfiguration == null) {
      return DrmSessionManager.DRM_UNSUPPORTED;
    }
    MediaItem.DrmConfiguration config = mediaItem.localConfiguration.drmConfiguration;
    synchronized (lock) {
      if (!Objects.equals(config, drmConfiguration)) {
        drmConfiguration = config;
        manager = createManager(config, dataSourceFactory);
      }
      return manager;
    }
  }

  private static DrmSessionManager createManager(
      @NonNull MediaItem.DrmConfiguration drmConfig,
      @NonNull DataSource.Factory dataSourceFactory) {
    Uri licenseUri = drmConfig.licenseUri;
    HttpMediaDrmCallback drmCallback =
        new HttpMediaDrmCallback(
            licenseUri != null ? licenseUri.toString() : null,
            drmConfig.forceDefaultLicenseUri,
            dataSourceFactory);

    for (Map.Entry<String, String> entry : drmConfig.licenseRequestHeaders.entrySet()) {
      drmCallback.setKeyRequestProperty(entry.getKey(), entry.getValue());
    }

    ExoMediaDrm.Provider l3MediaDrmProvider =
        uuid -> {
          try {
            FrameworkMediaDrm mediaDrm = FrameworkMediaDrm.newInstance(uuid);
            return new WidevineL3MediaDrm(uuid, mediaDrm);
          } catch (UnsupportedDrmException e) {
            Log.e(TAG, "Failed to instantiate FrameworkMediaDrm: " + e.getMessage());
            return new DummyExoMediaDrm();
          }
        };

    DefaultDrmSessionManager.Builder builder =
        new DefaultDrmSessionManager.Builder()
            .setUuidAndExoMediaDrmProvider(drmConfig.scheme, l3MediaDrmProvider)
            .setMultiSession(drmConfig.multiSession)
            .setPlayClearSamplesWithoutKeys(drmConfig.playClearContentWithoutKey);

    if (drmConfig.forcedSessionTrackTypes != null && !drmConfig.forcedSessionTrackTypes.isEmpty()) {
      builder.setUseDrmSessionsForClearContent(
          Ints.toArray(drmConfig.forcedSessionTrackTypes));
    }

    DefaultDrmSessionManager drmSessionManager = builder.build(drmCallback);
    byte[] keySetId = drmConfig.getKeySetId();
    drmSessionManager.setMode(DefaultDrmSessionManager.MODE_PLAYBACK, keySetId);
    return drmSessionManager;
  }
}
