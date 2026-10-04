const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {HttpsError, onCall, onRequest} = require("firebase-functions/v2/https");

initializeApp();

const db = getFirestore("trekit");
const auth = getAuth();
const storage = getStorage();
const options = {region: "us-central1", enforceAppCheck: false};
const browserCors = [
  "http://127.0.0.1:7357",
  "http://localhost:7357",
  "https://trekit.online",
  "https://trekit-10e88.web.app",
  "https://trekit-10e88.firebaseapp.com",
  /^https:\/\/trekit-10e88--[a-z0-9-]+\.web\.app$/,
];
const accountOptions = {
  ...options,
  timeoutSeconds: 540,
  memory: "512MiB",
};

function requireUser(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  return request.auth.uid;
}

function requireRecentlyAuthenticatedUser(request) {
  const userId = requireUser(request);
  const authTime = Number(request.auth.token.auth_time);
  const ageSeconds = Math.floor(Date.now() / 1000) - authTime;
  if (!Number.isFinite(authTime) || ageSeconds < 0 || ageSeconds > 5 * 60) {
    throw new HttpsError(
        "failed-precondition",
        "For your security, sign out and sign back in before deleting your account.",
    );
  }
  return userId;
}

function requireString(value, name, maxLength) {
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.trim().length > maxLength) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return value.trim();
}

async function requireTripOwner(tripId, userId) {
  const tripRef = db.collection("trips").doc(tripId);
  const trip = await tripRef.get();
  if (!trip.exists) {
    throw new HttpsError("not-found", "Trip not found.");
  }
  if (trip.get("ownerId") !== userId) {
    throw new HttpsError("permission-denied", "Only the trip owner can do that.");
  }
  return {tripRef, trip};
}

exports.shareTrip = onCall(options, async (request) => {
  const ownerId = requireUser(request);
  const tripId = requireString(request.data?.tripId, "Trip", 128);
  const email = requireString(request.data?.email, "Email", 254).toLowerCase();
  const role = request.data?.role;
  if (role !== "viewer" && role !== "editor") {
    throw new HttpsError("invalid-argument", "Choose viewer or editor access.");
  }

  const {tripRef} = await requireTripOwner(tripId, ownerId);
  let invitedUser;
  try {
    invitedUser = await auth.getUserByEmail(email);
  } catch (error) {
    if (error.code === "auth/user-not-found") {
      throw new HttpsError(
          "not-found",
          "That email does not have a TrekIt account yet.",
      );
    }
    throw error;
  }

  if (invitedUser.uid === ownerId) {
    throw new HttpsError("already-exists", "You already own this trip.");
  }
  if (!invitedUser.emailVerified) {
    throw new HttpsError(
        "failed-precondition",
        "That person needs to verify their TrekIt email before being added.",
    );
  }

  await tripRef.collection("members").doc(invitedUser.uid).set({
    userId: invitedUser.uid,
    role,
    createdBy: ownerId,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {userId: invitedUser.uid, email, role};
});

exports.removeTripMember = onCall(options, async (request) => {
  const ownerId = requireUser(request);
  const tripId = requireString(request.data?.tripId, "Trip", 128);
  const memberId = requireString(request.data?.memberId, "Member", 128);
  const {tripRef} = await requireTripOwner(tripId, ownerId);
  if (memberId === ownerId) {
    throw new HttpsError("failed-precondition", "The trip owner cannot be removed.");
  }
  await tripRef.collection("members").doc(memberId).delete();
  return {removed: true};
});

exports.deleteTrip = onCall(options, async (request) => {
  const ownerId = requireUser(request);
  const tripId = requireString(request.data?.tripId, "Trip", 128);
  const {tripRef, trip} = await requireTripOwner(tripId, ownerId);
  const entries = await tripRef.collection("entries").get();
  const imagePaths = entries.docs
      .map((entry) => entry.get("imagePath"))
      .filter((path) => typeof path === "string");
  const coverImagePath = trip.get("coverImagePath");
  if (typeof coverImagePath === "string") {
    imagePaths.push(coverImagePath);
  }

  await Promise.all(imagePaths.map(async (imagePath) => {
    try {
      await storage.bucket().file(imagePath).delete({ignoreNotFound: true});
    } catch (error) {
      console.error("Trip photo cleanup failed", {tripId, imagePath, error});
      throw new HttpsError(
          "internal",
          "The trip could not be deleted safely. Please try again.",
      );
    }
  }));

  await db.recursiveDelete(tripRef);
  return {deleted: true};
});

exports.listTripMembers = onCall(options, async (request) => {
  const ownerId = requireUser(request);
  const tripId = requireString(request.data?.tripId, "Trip", 128);
  const {tripRef} = await requireTripOwner(tripId, ownerId);
  const members = await tripRef.collection("members").limit(100).get();

  const result = await Promise.all(members.docs.map(async (member) => {
    const userId = member.get("userId");
    let email = "Account unavailable";
    try {
      email = (await auth.getUser(userId)).email || email;
    } catch (error) {
      if (error.code !== "auth/user-not-found") {
        throw error;
      }
    }
    return {userId, email, role: member.get("role")};
  }));

  result.sort((a, b) => a.email.localeCompare(b.email));
  return {members: result};
});

exports.deleteAccount = onCall(accountOptions, async (request) => {
  const userId = requireRecentlyAuthenticatedUser(request);
  const [ownedTrips, authoredEntries, memberships] = await Promise.all([
    db.collection("trips").where("ownerId", "==", userId).get(),
    db.collectionGroup("entries").where("authorId", "==", userId).get(),
    db.collectionGroup("members").where("userId", "==", userId).get(),
  ]);

  try {
    await storage.bucket().deleteFiles({prefix: `users/${userId}/`});
    await Promise.all(authoredEntries.docs.map((entry) => entry.ref.delete()));
    await Promise.all(ownedTrips.docs.map((trip) => db.recursiveDelete(trip.ref)));
    await Promise.all(memberships.docs.map((member) => member.ref.delete()));
    await db.collection("users").doc(userId).delete();
    await auth.deleteUser(userId);
  } catch (error) {
    console.error("Account deletion failed", {userId, error});
    throw new HttpsError(
        "internal",
        "Your account could not be completely deleted. Please try again.",
    );
  }

  return {deleted: true};
});

exports.getEntryPhoto = onRequest({
  region: "us-central1",
  cors: browserCors,
}, async (request, response) => {
  if (request.method !== "GET") {
    response.status(405).send("Method not allowed.");
    return;
  }

  const authorization = request.get("authorization") || "";
  if (!authorization.startsWith("Bearer ")) {
    response.status(401).send("Sign in to continue.");
    return;
  }

  let userId;
  try {
    userId = (await auth.verifyIdToken(authorization.slice(7))).uid;
  } catch (_) {
    response.status(401).send("Your session is no longer valid.");
    return;
  }

  let tripId;
  let entryId;
  try {
    tripId = requireString(request.query.tripId, "Trip", 128);
    entryId = requireString(request.query.entryId, "Entry", 128);
  } catch (error) {
    response.status(400).send(error.message);
    return;
  }

  const tripRef = db.collection("trips").doc(tripId);
  const [trip, membership, entry] = await Promise.all([
    tripRef.get(),
    tripRef.collection("members").doc(userId).get(),
    tripRef.collection("entries").doc(entryId).get(),
  ]);
  if (!trip.exists || !entry.exists) {
    response.status(404).send("Photo not found.");
    return;
  }
  if (trip.get("ownerId") !== userId && !membership.exists) {
    response.status(403).send("You do not have access to this photo.");
    return;
  }

  const imagePath = entry.get("imagePath");
  const expectedSuffix = `/trips/${tripId}/entries/${entryId}/photo`;
  if (typeof imagePath !== "string" || !imagePath.endsWith(expectedSuffix)) {
    response.status(404).send("Photo not found.");
    return;
  }

  const file = storage.bucket().file(imagePath);
  try {
    const [metadata] = await file.getMetadata();
    response.set("Content-Type", metadata.contentType || "image/jpeg");
    response.set("Cache-Control", "private, max-age=300");
    file.createReadStream()
        .on("error", () => {
          if (!response.headersSent) {
            response.status(404).send("Photo not found.");
          } else {
            response.end();
          }
        })
        .pipe(response);
  } catch (_) {
    response.status(404).send("Photo not found.");
  }
});

exports.getTripCover = onRequest({
  region: "us-central1",
  cors: browserCors,
}, async (request, response) => {
  if (request.method !== "GET") {
    response.status(405).send("Method not allowed.");
    return;
  }

  const authorization = request.get("authorization") || "";
  if (!authorization.startsWith("Bearer ")) {
    response.status(401).send("Sign in to continue.");
    return;
  }

  let userId;
  try {
    userId = (await auth.verifyIdToken(authorization.slice(7))).uid;
  } catch (_) {
    response.status(401).send("Your session is no longer valid.");
    return;
  }

  let tripId;
  try {
    tripId = requireString(request.query.tripId, "Trip", 128);
  } catch (error) {
    response.status(400).send(error.message);
    return;
  }

  const tripRef = db.collection("trips").doc(tripId);
  const [trip, membership] = await Promise.all([
    tripRef.get(),
    tripRef.collection("members").doc(userId).get(),
  ]);
  if (!trip.exists) {
    response.status(404).send("Cover not found.");
    return;
  }
  if (trip.get("ownerId") !== userId && !membership.exists) {
    response.status(403).send("You do not have access to this cover.");
    return;
  }

  const coverImagePath = trip.get("coverImagePath");
  const expectedPath = `users/${trip.get("ownerId")}/trips/${tripId}/cover`;
  if (coverImagePath !== expectedPath) {
    response.status(404).send("Cover not found.");
    return;
  }

  const file = storage.bucket().file(coverImagePath);
  try {
    const [metadata] = await file.getMetadata();
    response.set("Content-Type", metadata.contentType || "image/jpeg");
    response.set("Cache-Control", "private, max-age=300");
    file.createReadStream()
        .on("error", () => {
          if (!response.headersSent) {
            response.status(404).send("Cover not found.");
          } else {
            response.end();
          }
        })
        .pipe(response);
  } catch (_) {
    response.status(404).send("Cover not found.");
  }
});
