import LaunchMeetingOptions from "@/components/sites/zoom/launch-meeting-options";
import { ZoomFooter, ZoomHeader } from "@/components/sites/zoom/zoom-shell";

export default async function LaunchMeetingPage({
  params,
}: {
  params: Promise<{ meetingId: string }>;
}) {
  const { meetingId } = await params;

  return (
    <div id="zoom-ui-container" className="zoom-meeting-page NwR_O3JG">
      <ZoomHeader />
      <div id="zoom-ui-frame" className="KJngd7UG I0MG3p8Q" role="main" tabIndex={0}>
        <div className="At6Ofnrg AJKPZk_N dLDxYimD"><div className="jZWDYHYu" /></div>
        <div className="bhauZU7H launch-content-area">
          <LaunchMeetingOptions meetingId={meetingId} />
        </div>
      </div>
      <ZoomFooter />
    </div>
  );
}
