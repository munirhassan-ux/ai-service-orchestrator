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
export declare const notificationsQueue: AppNotification[];
export declare function pushNotification(roleTarget: "CUSTOMER" | "PROVIDER", bookingId: string, type: string, title: string, body: string): void;
//# sourceMappingURL=notifications.d.ts.map