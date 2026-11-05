import Image from "next/image";
import { BETTERDESK_LANDING_URL } from "@/lib/zoom-client-release";

export function ZoomHeader() {
  return (
    <div id="header_container" className="zoom-header-container" role="banner">
      <div id="header_outer" className="zoom-header-outer">
        <header id="header" className="zoom-site-header">
          <a className="zoom-home-link yLyeC3Mp" href={BETTERDESK_LANDING_URL} aria-label="BetterDesk homepage">
            <Image className="header-logo" src="/sites/zoom/zoom-logo.svg" alt="Zoom Logo" width={115} height={26} priority />
          </a>
          <div className="zoom-header-actions action-btns">
            <a href="https://support.zoom.us/hc/en-us" target="_blank" rel="noreferrer">Support</a>
            <details className="zoom-language-menu zoom-header-language Co1A6ZJW">
              <summary>English <span className="cVDRP5Ns" aria-hidden="true" /></summary>
              <div className="zoom-language-options">
                <span>English</span><span>Español</span><span>Deutsch</span><span>简体中文</span>
                <span>繁體中文</span><span>Français</span><span>Português</span><span>日本語</span>
                <span>Русский</span><span>한국어</span><span>Italiano</span><span>Tiếng Việt</span>
                <span>Polski</span><span>Türkçe</span><span>Bahasa Indonesia</span><span>Nederlands</span>
                <span>Svenska</span>
              </div>
            </details>
          </div>
        </header>
      </div>
    </div>
  );
}

export function ZoomFooter() {
  return (
    <footer id="footer_container" className="zoom-site-footer" role="contentinfo">
      <div id="footer">
        <p>©2026 Zoom Communications, Inc. <span>All rights reserved.</span></p>
        <nav className="zoom-footer-links LP3K7kSq" aria-label="Legal">
          <a href="https://zoom.us/en-us/trust" target="_blank" rel="noreferrer">Trust Center</a>
          <a href="https://zoom.us/en-us/acceptable-use-guidelines" target="_blank" rel="noreferrer">Acceptable Use Guidelines</a>
          <a href="https://zoom.us/en-us/trust/legal-compliance" target="_blank" rel="noreferrer">Legal &amp; Compliance</a>
          <button type="button">Do Not Sell My Personal Information</button>
          <button type="button">Cookie Preferences</button>
        </nav>
      </div>
    </footer>
  );
}
