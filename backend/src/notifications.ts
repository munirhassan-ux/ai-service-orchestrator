export interface AppNotification {
  id: string;
  title: string;
  body: string;
  roleTarget: "CUSTOMER" | "PROVIDER";
  bookingId: string;
  type: string;
  timestamp: string;
  read: boolean;
}

export const notificationsQueue: AppNotification[] = [];

export function pushNotification(
  roleTarget: "CUSTOMER" | "PROVIDER",
  bookingId: string,
  type: string,
  title: string,
  body: string
) {
  const notif: AppNotification = {
    id: `notif_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`,
    title,
    body,
    roleTarget,
    bookingId,
    type,
    timestamp: new Date().toISOString(),
    read: false,
  };
  notificationsQueue.push(notif);
  console.log(`[PushNotification] Target: ${roleTarget} | Type: ${type} | Msg: ${body}`);
}
