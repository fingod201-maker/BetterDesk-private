import BrowserJoinFlow from "@/components/sites/zoom/browser-join-flow";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Join Meeting - Zoom",
};

export default async function BrowserMeetingPage({
  params,
}: {
  params: Promise<{ meetingId: string }>;
}) {
  const { meetingId } = await params;

  return <BrowserJoinFlow meetingId={meetingId} />;
}
