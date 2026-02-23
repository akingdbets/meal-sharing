import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";

admin.initializeApp();

/**
 * 소셜 로그인(카카오/네이버 등) 후 Firebase 커스텀 인증용 토큰 발급.
 * 클라이언트가 UID로 쓸 값을 그대로 받아 createCustomToken(uid)로 토큰 발급.
 * (카카오: kakao_${id}, 네이버: naver_${id} 등 접두사는 클라이언트에서 붙여 전달)
 * 리전: asia-northeast3 (서울). Flutter 클라이언트 _functionsRegion 과 동일해야 함.
 */
export const createCustomToken = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    // V2 onCall: 클라이언트가 보낸 데이터는 request.data 객체 그 자체
    console.log("전달된 전체 데이터:", JSON.stringify(request.data));

    const data = request.data as Record<string, unknown> | null | undefined;
    const kakaoUserId = data?.kakaoUserId ?? data?.kakao_user_id;

    if (kakaoUserId == null || kakaoUserId === "") {
      throw new HttpsError(
        "invalid-argument",
        "kakaoUserId is required"
      );
    }

    // 클라이언트가 준 값을 그대로 UID로 사용 (카카오: kakao_xxx, 네이버: naver_xxx)
    const uid = String(kakaoUserId);

    let token: string;
    try {
      token = await admin.auth().createCustomToken(uid);
    } catch (err) {
      console.error("createCustomToken 실패:", err);
      throw new HttpsError(
        "internal",
        err instanceof Error ? err.message : "Failed to create custom token"
      );
    }

    console.log("토큰 생성 성공, uid:", uid);
    return { token };
  }
);

/**
 * users/{userId}/notifications/{notificationId} 문서가 생성될 때
 * 해당 유저의 FCM 토큰들로 푸시 알림 발송.
 * 무효 토큰은 fcmTokens 서브컬렉션에서 삭제.
 */
export const sendPushOnNotificationCreate = onDocumentCreated(
  {
    document: "users/{userId}/notifications/{notificationId}",
    region: "asia-northeast3",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    const userId = event.params.userId as string;
    const notificationId = event.params.notificationId as string;
    const title = (data?.title as string) ?? "알림";
    const body = (data?.body as string) ?? "";
    const postId = (data?.postId as string) ?? "";
    const type = (data?.type as string) ?? "";
    const senderId = (data?.senderId as string) ?? "";

    const db = admin.firestore();

    // 알림 수신 유저의 알림 설정 확인 (꺼져 있으면 푸시 미발송)
    const userSnap = await db.collection("users").doc(userId).get();
    const userData = userSnap.data();
    const typeLower = type.toLowerCase();
    if (typeLower === "comment" && userData?.notificationComments === false) {
      console.log(`sendPushOnNotificationCreate: user ${userId} has notificationComments off, skip`);
      return;
    }
    if (typeLower === "follow" && userData?.notificationFollows === false) {
      console.log(`sendPushOnNotificationCreate: user ${userId} has notificationFollows off, skip`);
      return;
    }
    if (typeLower === "community" && userData?.notificationCommunity === false) {
      console.log(`sendPushOnNotificationCreate: user ${userId} has notificationCommunity off, skip`);
      return;
    }

    const tokensSnap = await db
      .collection("users")
      .doc(userId)
      .collection("fcmTokens")
      .get();

    const tokens: string[] = [];
    const tokenDocIds: string[] = [];
    tokensSnap.docs.forEach((doc) => {
      const t = doc.data().token as string | undefined;
      if (t && typeof t === "string" && t.length > 0) {
        tokens.push(t);
        tokenDocIds.push(doc.id);
      }
    });

    if (tokens.length === 0) {
      console.log(`sendPushOnNotificationCreate: no FCM tokens for user ${userId}`);
      return;
    }

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: { title, body },
      data: {
        type,
        postId: postId || "",
        notificationId: notificationId || "",
        senderId: senderId || "",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "meal_sharing_alerts",
          priority: "high" as const,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);

      response.responses.forEach((resp, idx) => {
        if (!resp.success && resp.error) {
          const code = resp.error.code;
          const isInvalidToken =
            code === "messaging/invalid-registration-token" ||
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-argument";
          if (isInvalidToken && tokenDocIds[idx]) {
            db.collection("users")
              .doc(userId)
              .collection("fcmTokens")
              .doc(tokenDocIds[idx])
              .delete()
              .then(() => console.log(`Removed invalid token doc: ${tokenDocIds[idx]}`))
              .catch((err) => console.error("Error removing invalid token doc:", err));
          }
        }
      });

      console.log(`sendPushOnNotificationCreate: sent to ${response.successCount}/${tokens.length} tokens for user ${userId}`);
    } catch (err) {
      console.error("sendPushOnNotificationCreate error:", err);
      throw err;
    }
  }
);
