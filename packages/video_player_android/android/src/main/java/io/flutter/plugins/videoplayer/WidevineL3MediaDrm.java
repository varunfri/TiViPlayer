// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.media.MediaCryptoException;
import android.media.MediaDrmException;
import android.media.NotProvisionedException;
import android.media.DeniedByServerException;
import android.os.PersistableBundle;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.C;
import androidx.media3.common.DrmInitData;
import androidx.media3.common.util.Log;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.decoder.CryptoConfig;
import androidx.media3.exoplayer.analytics.PlayerId;
import androidx.media3.exoplayer.drm.ExoMediaDrm;
import androidx.media3.exoplayer.drm.FrameworkCryptoConfig;
import androidx.media3.exoplayer.drm.FrameworkMediaDrm;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * An {@link ExoMediaDrm} wrapper that forces Widevine L3 (software / non-secure video path).
 *
 * <p>Flutter's {@code video_player} renders video into an OpenGL {@code SurfaceTexture} via
 * {@code SurfaceProducer}. On physical Android devices, Widevine defaults to L1 (hardware TEE),
 * which requires a secure video decoder (e.g. {@code c2.*.secure}). Android hardware security
 * policy strictly prohibits secure decoders from rendering into non-secure {@code SurfaceTexture}
 * targets, resulting in audio playing with a completely black video screen.
 *
 * <p>By forcing the Widevine CDM security level to "L3" and ensuring {@link #requiresSecureDecoder}
 * returns {@code false}, ExoPlayer selects a non-secure hardware video decoder that can render
 * directly onto Flutter's {@code SurfaceTexture} without blanking out video frames.
 */
@UnstableApi
public final class WidevineL3MediaDrm implements ExoMediaDrm {
  private static final String TAG = "WidevineL3MediaDrm";
  private final FrameworkMediaDrm delegate;
  private final UUID uuid;

  public WidevineL3MediaDrm(@NonNull UUID uuid, @NonNull FrameworkMediaDrm delegate) {
    this.uuid = uuid;
    this.delegate = delegate;
    if (C.WIDEVINE_UUID.equals(uuid)) {
      try {
        delegate.setPropertyString("securityLevel", "L3");
        Log.i(TAG, "Successfully forced Widevine securityLevel to L3 for Flutter SurfaceTexture");
      } catch (Exception e) {
        Log.w(TAG, "Could not set Widevine securityLevel to L3: " + e.getMessage());
      }
    }
  }

  @Override
  public void setOnEventListener(@Nullable OnEventListener listener) {
    delegate.setOnEventListener(listener);
  }

  @Override
  public void setOnKeyStatusChangeListener(@Nullable OnKeyStatusChangeListener listener) {
    delegate.setOnKeyStatusChangeListener(listener);
  }

  @Override
  public void setOnExpirationUpdateListener(@Nullable OnExpirationUpdateListener listener) {
    delegate.setOnExpirationUpdateListener(listener);
  }

  @NonNull
  @Override
  public byte[] openSession() throws MediaDrmException {
    return delegate.openSession();
  }

  @Override
  public void closeSession(@NonNull byte[] sessionId) {
    delegate.closeSession(sessionId);
  }

  @Override
  public void setPlayerIdForSession(@NonNull byte[] sessionId, @NonNull PlayerId playerId) {
    delegate.setPlayerIdForSession(sessionId, playerId);
  }

  @NonNull
  @Override
  public KeyRequest getKeyRequest(
      @NonNull byte[] scope,
      @Nullable List<DrmInitData.SchemeData> schemeDatas,
      int keyType,
      @Nullable HashMap<String, String> optionalParameters)
      throws NotProvisionedException {
    return delegate.getKeyRequest(scope, schemeDatas, keyType, optionalParameters);
  }

  @Nullable
  @Override
  public byte[] provideKeyResponse(@NonNull byte[] scope, @NonNull byte[] response)
      throws NotProvisionedException, DeniedByServerException {
    return delegate.provideKeyResponse(scope, response);
  }

  @NonNull
  @Override
  public ProvisionRequest getProvisionRequest() {
    return delegate.getProvisionRequest();
  }

  @Override
  public void provideProvisionResponse(@NonNull byte[] response) throws DeniedByServerException {
    delegate.provideProvisionResponse(response);
  }

  @NonNull
  @Override
  public Map<String, String> queryKeyStatus(@NonNull byte[] sessionId) {
    return delegate.queryKeyStatus(sessionId);
  }

  @Override
  public boolean requiresSecureDecoder(@NonNull byte[] sessionId, @NonNull String mimeType) {
    // Crucial: Flutter SurfaceTexture cannot accept secure decoder output on physical devices.
    // Forcing this to false allows ExoPlayer to pick a standard non-secure video decoder.
    return false;
  }

  @Override
  public void acquire() {
    delegate.acquire();
  }

  @Override
  public void release() {
    delegate.release();
  }

  @Override
  public void restoreKeys(@NonNull byte[] sessionId, @NonNull byte[] keySetId) {
    delegate.restoreKeys(sessionId, keySetId);
  }

  @Override
  public void removeOfflineLicense(@NonNull byte[] keySetId) {
    delegate.removeOfflineLicense(keySetId);
  }

  @Nullable
  @Override
  public List<byte[]> getOfflineLicenseKeySetIds() {
    return delegate.getOfflineLicenseKeySetIds();
  }

  @Nullable
  @Override
  public PersistableBundle getMetrics() {
    return delegate.getMetrics();
  }

  @NonNull
  @Override
  public String getPropertyString(@NonNull String propertyName) {
    return delegate.getPropertyString(propertyName);
  }

  @NonNull
  @Override
  public byte[] getPropertyByteArray(@NonNull String propertyName) {
    return delegate.getPropertyByteArray(propertyName);
  }

  @Override
  public void setPropertyString(@NonNull String propertyName, @NonNull String value) {
    delegate.setPropertyString(propertyName, value);
  }

  @Override
  public void setPropertyByteArray(@NonNull String propertyName, @NonNull byte[] value) {
    delegate.setPropertyByteArray(propertyName, value);
  }

  @NonNull
  @Override
  public CryptoConfig createCryptoConfig(@NonNull byte[] sessionId) throws MediaCryptoException {
    CryptoConfig config = delegate.createCryptoConfig(sessionId);
    if (config instanceof FrameworkCryptoConfig) {
      FrameworkCryptoConfig fcc = (FrameworkCryptoConfig) config;
      // Explicitly allow insecure decoder components so ExoPlayer can match standard hardware decoders.
      return new FrameworkCryptoConfig(fcc.uuid, fcc.sessionId, /* forceAllowInsecureDecoderComponents= */ true);
    }
    return config;
  }

  @Override
  public int getCryptoType() {
    return delegate.getCryptoType();
  }
}
