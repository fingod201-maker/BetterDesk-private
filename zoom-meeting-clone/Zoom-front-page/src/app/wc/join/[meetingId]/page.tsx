import JoinMeetingForm from "@/components/sites/zoom/join-meeting-form";
import { ZoomFooter, ZoomHeader } from "@/components/sites/zoom/zoom-shell";
import { redirect } from "next/navigation";

export default async function MeetingPage({
  params,
  searchParams,
}: {
  params: Promise<{ meetingId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { meetingId } = await params;
  const query = await searchParams;
  const queryString = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (typeof value === "string") queryString.set(key, value);
    else if (Array.isArray(value)) value.forEach((item) => queryString.append(key, item));
  }
  const queryText = queryString.toString();
  redirect(`/wc/${meetingId}/join${queryText ? `?${queryText}` : ""}`);
}
