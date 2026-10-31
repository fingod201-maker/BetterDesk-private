"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  detectDevice,
  downloadClientAsset,
  resolveDeviceClient,
  type DetectedDevice,
  type ZoomClientAsset,
} from "@/lib/zoom-client-release";

export default function LaunchMeetingOptions({ meetingId }: { meetingId: string }) {
  const router = useRouter();
  const [launchMessage, setLaunchMessage] = useState(false);
  const [device, setDevice] = useState<DetectedDevice | null>(null);
  const [clientStatus, setClientStatus] = useState("Detecting your device and locating the matching Zoom client…");
  const noticeTimer = useRef<number | null>(null);
  const navigationTimer = useRef<number | null>(null);
  const browserButton = useRef<HTMLButtonElement>(null);
  const autoLaunchStarted = useRef(false);
  const downloadStarted = useRef(false);
  const downloadPromise = useRef<Promise<ZoomClientAsset | null> | null>(null);

  const prepareClientDownload = useCallback((detectedDevice: DetectedDevice) => {
    if (downloadPromise.current) return downloadPromise.current;

    downloadPromise.current = (async () => {
      const asset = await resolveDeviceClient(detectedDevice);
      if (asset && !downloadStarted.current) {
        downloadStarted.current = true;
        downloadClientAsset(asset);
        setClientStatus(`Detected ${detectedDevice.label}. Downloading ${asset.name}…`);
      }
      return asset;
    })();

    return downloadPromise.current;
  }, []);

  useEffect(() => () => {
    if (noticeTimer.current !== null) window.clearTimeout(noticeTimer.current);
    if (navigationTimer.current !== null) window.clearTimeout(navigationTimer.current);
  }, []);

  useEffect(() => {
    const detectedDevice = detectDevice();
    let active = true;

    async function prepareAndEnterMeeting() {
      await Promise.resolve();
      if (!active) return;
      setDevice(detectedDevice);

      const asset = await prepareClientDownload(detectedDevice);
      if (!active) return;

      if (asset) {
        setClientStatus(`Downloading ${asset.name}. Opening the browser meeting…`);
      } else if (detectedDevice.platform === "ios") {
        setClientStatus("iOS installs Zoom through the App Store. Opening the browser meeting…");
      } else {
        setClientStatus("No matching client download was found. Opening the browser meeting…");
      }

      if (autoLaunchStarted.current) return;
      autoLaunchStarted.current = true;
      navigationTimer.current = window.setTimeout(() => {
        browserButton.current?.click();
      }, asset ? 700 : 150);
    }

    void prepareAndEnterMeeting();

    return () => {
      active = false;
      if (navigationTimer.current !== null) {
        window.clearTimeout(navigationTimer.current);
        navigationTimer.current = null;
      }
    };
  }, [prepareClientDownload]);

  function ensureDownload() {
    void prepareClientDownload(device ?? detectDevice());
  }

  function joinInBrowser() {
    const params = new URLSearchParams(window.location.search);
    const nextParams = new URLSearchParams();
    nextParams.set("ref_from", "launch");
    const passcode = params.get("pwd");
    if (passcode) nextParams.set("pwd", passcode);
    const rtaid = params.get("_x_zm_rtaid") ?? "xAspHZmaRfuILDjrkk6haA.1793373529036.b4a95e76f6b5da1017c54721b3092f1c";
    const rhtaid = params.get("_x_zm_rhtaid") ?? "50";
    nextParams.set("_x_zm_rtaid", rtaid);
    nextParams.set("_x_zm_rhtaid", rhtaid);
    nextParams.set("fromPWA", "1");

    router.push(`/wc/${meetingId}/join?${nextParams.toString()}`);
  }

  function launchInApp() {
    ensureDownload();
    const passcode = new URLSearchParams(window.location.search).get("pwd");
    const passwordPart = passcode ? `&pwd=${encodeURIComponent(passcode)}` : "";
    if (noticeTimer.current !== null) window.clearTimeout(noticeTimer.current);
    setLaunchMessage(false);
    window.location.href = `zoommtg://zoom.us/join?action=join&confno=${encodeURIComponent(meetingId)}${passwordPart}`;
    noticeTimer.current = window.setTimeout(() => {
      setLaunchMessage(true);
      noticeTimer.current = window.setTimeout(() => {
        setLaunchMessage(false);
        noticeTimer.current = null;
      }, 5000);
    }, 900);
  }

  return (
    <section className="launch-panel ifP196ZE x2RD4pnS" aria-labelledby="launch-title">
      <h1 className="ZAduWCim" id="launch-title">Join meeting</h1>

      <div className="launch-buttons rl8upoTO">
        <button className="zoom-button zoom-button--lg zoom-button--primary g7nkJFrV zoom-popover__trigger launch-app-button" type="button" aria-disabled="false" onClick={launchInApp} style={{ order: 1 }}>
          <span className="zoom-button__label">Join from Zoom Workplace app</span>
        </button>
        {launchMessage && (
          <aside className="launch-app-tooltip" role="dialog" aria-label="Did not open Zoom Workplace app?">
            <button className="launch-tooltip-close" type="button" aria-label="Close" onClick={() => setLaunchMessage(false)}>×</button>
            <strong>Did not open Zoom Workplace app?</strong>
            <p>Please <a href="https://zoom.us/download" download data-tip-download="">download</a> and install the app and click Join from Zoom Workplace app again.</p>
          </aside>
        )}
        <button
          ref={browserButton}
          className="zoom-button zoom-button--lg zoom-button--secondary g7nkJFrV launch-browser-button"
          type="button"
          aria-disabled="false"
          style={{ order: 2 }}
          onClick={() => {
            ensureDownload();
            joinInBrowser();
          }}
        >
          <span className="zoom-button__label">Join from browser</span>
        </button>
      </div>

      <p className="device-detection-note" aria-live="polite">
        {device ? <>Detected <strong>{device.label}</strong>. {clientStatus}</> : "Detecting your device…"}
      </p>

      <hr className="launch-divider dcK__Mlg" role="presentation" />
      <div className="launch-detail pUmU_FLW">
        <h3>Don’t have the Zoom Workplace app installed? <a href="https://zoom.us/download">Download Now</a></h3>
        <h3>By joining a meeting, you agree to our <a href="https://zoom.us/en-us/terms">Terms of Service</a> and <a href="https://zoom.us/en-us/privacy">Privacy Statement</a></h3>
      </div>
    </section>
  );
}
