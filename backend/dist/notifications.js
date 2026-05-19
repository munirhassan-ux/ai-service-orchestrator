export const notificationsQueue = [];
export function pushNotification(roleTarget, bookingId, type, title, body) {
    const notif = {
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
//# sourceMappingURL=notifications.js.map