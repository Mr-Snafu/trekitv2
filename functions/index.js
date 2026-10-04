const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {FieldValue, getFirestore, Timestamp} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {HttpsError, onCall, onRequest} = require("firebase-functions/v2/https");
const crypto = require("node:crypto");

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

function requireOptionalString(value, name, maxLength) {
  if (typeof value !== "string" || value.trim().length > maxLength) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return value.trim();
}

function requireBoolean(value, name) {
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return value;
}

function requireTrekId(value) {
  const trekId = requireString(value, "TrekIt ID", 18).toUpperCase();
  if (!/^TREK-[A-Z0-9]{7,12}$/.test(trekId)) {
    throw new HttpsError("invalid-argument", "Enter a valid TrekIt ID.");
  }
  return trekId;
}

function displayNameFor(user) {
  const displayName = user.displayName?.trim();
  if (displayName && displayName.length <= 80) {
    return displayName;
  }
  return "TrekIt Explorer";
}

async function ensureCircleProfile(userId) {
  const profileRef = db.collection("circleProfiles").doc(userId);
  const existing = await profileRef.get();
  const user = await auth.getUser(userId);
  const displayName = displayNameFor(user);
  if (existing.exists) {
    if (existing.get("displayName") !== displayName) {
      await profileRef.update({displayName, updatedAt: FieldValue.serverTimestamp()});
    }
    return {userId, trekId: existing.get("trekId"), displayName};
  }

  const digest = crypto.createHash("sha256").update(userId).digest("hex").toUpperCase();
  for (let length = 7; length <= 12; length++) {
    const trekId = `TREK-${digest.slice(0, length)}`;
    const idRef = db.collection("trekIds").doc(trekId);
    const created = await db.runTransaction(async (transaction) => {
      const [reservation, profile] = await Promise.all([
        transaction.get(idRef),
        transaction.get(profileRef),
      ]);
      if (profile.exists) {
        return {userId, trekId: profile.get("trekId"), displayName};
      }
      if (reservation.exists && reservation.get("userId") !== userId) {
        return null;
      }
      const now = FieldValue.serverTimestamp();
      transaction.set(idRef, {userId, createdAt: now});
      transaction.set(profileRef, {
        userId,
        trekId,
        displayName,
        createdAt: now,
        updatedAt: now,
      });
      return {userId, trekId, displayName};
    });
    if (created) return created;
  }
  throw new HttpsError("internal", "A TrekIt ID could not be created.");
}

function circleItem(snapshot) {
  const data = snapshot.data();
  return {
    userId: data.userId,
    displayName: data.displayName,
    trekId: data.trekId,
    status: data.status || "connected",
    createdAt: data.createdAt?.toDate?.().toISOString() || null,
    retryAfter: data.retryAfter?.toDate?.().toISOString() || null,
  };
}

function userCircleRef(userId, collection, otherUserId) {
  return db.collection("users").doc(userId)
      .collection(collection).doc(otherUserId);
}

function profileResult(user, data = {}) {
  return {
    userId: user.uid,
    email: user.email || "",
    emailVerified: user.emailVerified,
    displayName: data.displayName || user.displayName || "TrekIt Explorer",
    bio: data.bio || "",
    notifyCircleRequests: data.notifyCircleRequests !== false,
    notifyAdventureActivity: data.notifyAdventureActivity !== false,
    allowCircleRequests: data.allowCircleRequests !== false,
  };
}

exports.getProfileState = onCall(options, async (request) => {
  const userId = requireUser(request);
  const [user, profile] = await Promise.all([
    auth.getUser(userId),
    db.collection("users").doc(userId).get(),
  ]);
  return profileResult(user, profile.data());
});

exports.updateProfile = onCall(options, async (request) => {
  const userId = requireUser(request);
  const displayName = requireString(
      request.data?.displayName, "Display name", 80);
  const bio = requireOptionalString(request.data?.bio, "Bio", 240);
  const notifyCircleRequests = requireBoolean(
      request.data?.notifyCircleRequests, "Circle notification preference");
  const notifyAdventureActivity = requireBoolean(
      request.data?.notifyAdventureActivity,
      "Adventure notification preference",
  );
  const allowCircleRequests = requireBoolean(
      request.data?.allowCircleRequests, "Circle privacy preference");
  const userRef = db.collection("users").doc(userId);
  const circleProfileRef = db.collection("circleProfiles").doc(userId);
  const [user, existingProfile, circleProfile, circle, incoming, outgoing,
    blocked] = await Promise.all([
    auth.getUser(userId),
    userRef.get(),
    circleProfileRef.get(),
    db.collectionGroup("circle").where("userId", "==", userId).limit(100).get(),
    db.collectionGroup("incomingRequests")
        .where("userId", "==", userId).limit(100).get(),
    db.collectionGroup("outgoingRequests")
        .where("userId", "==", userId).limit(100).get(),
    db.collectionGroup("blocked")
        .where("userId", "==", userId).limit(100).get(),
  ]);

  await auth.updateUser(userId, {displayName});
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(userRef, {
    "uid": userId,
    "email": user.email || "",
    "displayName": displayName,
    "bio": bio,
    "notifyCircleRequests": notifyCircleRequests,
    "notifyAdventureActivity": notifyAdventureActivity,
    "allowCircleRequests": allowCircleRequests,
    updatedAt: now,
    ...(!existingProfile.exists ? {createdAt: now} : {}),
  }, {merge: true});
  if (circleProfile.exists) {
    batch.update(circleProfileRef, {displayName, updatedAt: now});
  }
  for (const snapshot of [circle, incoming, outgoing, blocked]) {
    for (const document of snapshot.docs) {
      batch.update(document.ref, {displayName});
    }
  }
  await batch.commit();
  return profileResult({
    uid: user.uid,
    email: user.email,
    emailVerified: user.emailVerified,
    displayName,
  }, {
    displayName,
    bio,
    notifyCircleRequests,
    notifyAdventureActivity,
    allowCircleRequests,
  });
});

function exportValue(value) {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(exportValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
        Object.entries(value).map(([key, item]) => [key, exportValue(item)]),
    );
  }
  return value;
}

function exportDocuments(snapshot, limit) {
  return snapshot.docs.slice(0, limit).map((document) => ({
    id: document.id,
    path: document.ref.path,
    ...exportValue(document.data()),
  }));
}

exports.exportMyData = onCall(options, async (request) => {
  const userId = requireUser(request);
  const limit = 500;
  const userRef = db.collection("users").doc(userId);
  const [user, profile, circleProfile, ownedTrips, entries, snippets, comments,
    memberships, circle, incoming, outgoing, blocked] = await Promise.all([
    auth.getUser(userId),
    userRef.get(),
    db.collection("circleProfiles").doc(userId).get(),
    db.collection("trips").where("ownerId", "==", userId).limit(limit + 1).get(),
    db.collectionGroup("entries").where("authorId", "==", userId)
        .limit(limit + 1).get(),
    db.collectionGroup("snippets").where("authorId", "==", userId)
        .limit(limit + 1).get(),
    db.collectionGroup("comments").where("authorId", "==", userId)
        .limit(limit + 1).get(),
    db.collectionGroup("members").where("userId", "==", userId)
        .limit(limit + 1).get(),
    userRef.collection("circle").limit(100).get(),
    userRef.collection("incomingRequests").limit(100).get(),
    userRef.collection("outgoingRequests").limit(100).get(),
    userRef.collection("blocked").limit(100).get(),
  ]);
  return {
    exportVersion: 1,
    exportedAt: new Date().toISOString(),
    account: {
      userId,
      email: user.email || "",
      emailVerified: user.emailVerified,
      displayName: user.displayName || "",
      createdAt: user.metadata.creationTime || null,
      lastSignInAt: user.metadata.lastSignInTime || null,
    },
    profile: profile.exists ? exportValue(profile.data()) : null,
    circleProfile: circleProfile.exists ?
      exportValue(circleProfile.data()) : null,
    ownedAdventures: exportDocuments(ownedTrips, limit),
    authoredEntries: exportDocuments(entries, limit),
    authoredSnippets: exportDocuments(snippets, limit),
    authoredComments: exportDocuments(comments, limit),
    adventureMemberships: exportDocuments(memberships, limit),
    circle: exportDocuments(circle, 100),
    incomingCircleRequests: exportDocuments(incoming, 100),
    outgoingCircleRequests: exportDocuments(outgoing, 100),
    blockedUsers: exportDocuments(blocked, 100),
    truncated: {
      ownedAdventures: ownedTrips.size > limit,
      authoredEntries: entries.size > limit,
      authoredSnippets: snippets.size > limit,
      authoredComments: comments.size > limit,
      adventureMemberships: memberships.size > limit,
    },
  };
});

exports.getCircleState = onCall(options, async (request) => {
  const userId = requireUser(request);
  const profile = await ensureCircleProfile(userId);
  const userRef = db.collection("users").doc(userId);
  const [circle, incoming, outgoing, blocked] = await Promise.all([
    userRef.collection("circle").limit(100).get(),
    userRef.collection("incomingRequests").limit(100).get(),
    userRef.collection("outgoingRequests").limit(100).get(),
    userRef.collection("blocked").limit(100).get(),
  ]);
  return {
    profile,
    circle: circle.docs.map(circleItem),
    incoming: incoming.docs.map(circleItem),
    outgoing: outgoing.docs.map(circleItem),
    blocked: blocked.docs.map(circleItem),
  };
});

exports.sendCircleRequest = onCall(options, async (request) => {
  const userId = requireUser(request);
  const trekId = requireTrekId(request.data?.trekId);
  const [sender, idSnapshot] = await Promise.all([
    ensureCircleProfile(userId),
    db.collection("trekIds").doc(trekId).get(),
  ]);
  if (!idSnapshot.exists) {
    throw new HttpsError("not-found", "No account has that TrekIt ID.");
  }
  const targetId = idSnapshot.get("userId");
  if (targetId === userId) {
    throw new HttpsError("failed-precondition", "That is your own TrekIt ID.");
  }
  const target = await ensureCircleProfile(targetId);
  const senderOutgoing = userCircleRef(userId, "outgoingRequests", targetId);
  const targetIncoming = userCircleRef(targetId, "incomingRequests", userId);
  await db.runTransaction(async (transaction) => {
    const checks = await Promise.all([
      transaction.get(userCircleRef(userId, "blocked", targetId)),
      transaction.get(userCircleRef(targetId, "blocked", userId)),
      transaction.get(userCircleRef(userId, "circle", targetId)),
      transaction.get(userCircleRef(userId, "incomingRequests", targetId)),
      transaction.get(senderOutgoing),
      transaction.get(db.collection("users").doc(targetId)),
    ]);
    if (checks[0].exists) {
      throw new HttpsError("failed-precondition", "Unblock this person first.");
    }
    if (checks[1].exists) {
      throw new HttpsError("failed-precondition", "That request cannot be sent.");
    }
    if (checks[5].exists && checks[5].get("allowCircleRequests") === false) {
      throw new HttpsError("failed-precondition", "That request cannot be sent.");
    }
    if (checks[2].exists) {
      throw new HttpsError(
          "already-exists", "This person is already in your Circle.");
    }
    if (checks[3].exists) {
      throw new HttpsError(
          "failed-precondition", "This person already invited you.");
    }
    if (checks[4].exists) {
      const retryAfter = checks[4].get("retryAfter")?.toDate?.();
      if (checks[4].get("status") === "pending" ||
          (retryAfter && retryAfter > new Date())) {
        throw new HttpsError(
            "already-exists",
            "A request is already pending or cooling down.",
        );
      }
    }
    const now = FieldValue.serverTimestamp();
    transaction.set(
        senderOutgoing, {...target, status: "pending", createdAt: now});
    transaction.set(
        targetIncoming, {...sender, status: "pending", createdAt: now});
  });
  return {sent: true};
});

exports.acceptCircleRequest = onCall(options, async (request) => {
  const userId = requireUser(request);
  const otherUserId = requireString(request.data?.userId, "Person", 128);
  const [self, other] = await Promise.all([
    ensureCircleProfile(userId),
    ensureCircleProfile(otherUserId),
  ]);
  const incomingRef = userCircleRef(userId, "incomingRequests", otherUserId);
  await db.runTransaction(async (transaction) => {
    const [incoming, selfBlocked, otherBlocked] = await Promise.all([
      transaction.get(incomingRef),
      transaction.get(userCircleRef(userId, "blocked", otherUserId)),
      transaction.get(userCircleRef(otherUserId, "blocked", userId)),
    ]);
    if (!incoming.exists || incoming.get("status") !== "pending") {
      throw new HttpsError(
          "not-found", "That invitation is no longer available.");
    }
    if (selfBlocked.exists || otherBlocked.exists) {
      throw new HttpsError(
          "failed-precondition", "That invitation cannot be accepted.");
    }
    const now = FieldValue.serverTimestamp();
    transaction.set(
        userCircleRef(userId, "circle", otherUserId),
        {...other, createdAt: now},
    );
    transaction.set(
        userCircleRef(otherUserId, "circle", userId),
        {...self, createdAt: now},
    );
    transaction.delete(incomingRef);
    transaction.delete(
        userCircleRef(otherUserId, "outgoingRequests", userId));
  });
  return {accepted: true};
});

exports.declineCircleRequest = onCall(options, async (request) => {
  const userId = requireUser(request);
  const otherUserId = requireString(request.data?.userId, "Person", 128);
  const incomingRef = userCircleRef(userId, "incomingRequests", otherUserId);
  const incoming = await incomingRef.get();
  if (!incoming.exists) {
    throw new HttpsError("not-found", "That invitation is no longer available.");
  }
  const retryAfter = Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000);
  const batch = db.batch();
  batch.delete(incomingRef);
  batch.update(userCircleRef(otherUserId, "outgoingRequests", userId), {
    status: "cooldown",
    retryAfter,
  });
  await batch.commit();
  return {declined: true};
});

exports.removeCircleMember = onCall(options, async (request) => {
  const userId = requireUser(request);
  const otherUserId = requireString(request.data?.userId, "Person", 128);
  const batch = db.batch();
  batch.delete(userCircleRef(userId, "circle", otherUserId));
  batch.delete(userCircleRef(otherUserId, "circle", userId));
  await batch.commit();
  return {removed: true};
});

exports.blockCircleMember = onCall(options, async (request) => {
  const userId = requireUser(request);
  const otherUserId = requireString(request.data?.userId, "Person", 128);
  if (otherUserId === userId) {
    throw new HttpsError("failed-precondition", "You cannot block yourself.");
  }
  const relatedSnapshots = await Promise.all([
    userCircleRef(userId, "circle", otherUserId).get(),
    userCircleRef(userId, "incomingRequests", otherUserId).get(),
    userCircleRef(userId, "outgoingRequests", otherUserId).get(),
  ]);
  if (!relatedSnapshots.some((snapshot) => snapshot.exists)) {
    throw new HttpsError(
        "failed-precondition", "That person is not connected to this account.");
  }
  const other = await ensureCircleProfile(otherUserId);
  const batch = db.batch();
  batch.set(userCircleRef(userId, "blocked", otherUserId), {
    ...other,
    createdAt: FieldValue.serverTimestamp(),
  });
  for (const [owner, collection, target] of [
    [userId, "circle", otherUserId],
    [otherUserId, "circle", userId],
    [userId, "incomingRequests", otherUserId],
    [userId, "outgoingRequests", otherUserId],
    [otherUserId, "incomingRequests", userId],
    [otherUserId, "outgoingRequests", userId],
  ]) {
    batch.delete(userCircleRef(owner, collection, target));
  }
  await batch.commit();
  return {blocked: true};
});

exports.unblockCircleMember = onCall(options, async (request) => {
  const userId = requireUser(request);
  const otherUserId = requireString(request.data?.userId, "Person", 128);
  await userCircleRef(userId, "blocked", otherUserId).delete();
  return {unblocked: true};
});

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

exports.deleteJournalEntry = onCall(options, async (request) => {
  const userId = requireUser(request);
  const tripId = requireString(request.data?.tripId, "Trip", 128);
  const entryId = requireString(request.data?.entryId, "Entry", 128);
  const tripRef = db.collection("trips").doc(tripId);
  const entryRef = tripRef.collection("entries").doc(entryId);
  const [trip, entry, membership] = await Promise.all([
    tripRef.get(),
    entryRef.get(),
    tripRef.collection("members").doc(userId).get(),
  ]);
  if (!trip.exists || !entry.exists) {
    throw new HttpsError("not-found", "Journal entry not found.");
  }
  const isOwner = trip.get("ownerId") === userId;
  const isMemberAuthor = membership.exists && entry.get("authorId") === userId;
  if (!isOwner && !isMemberAuthor) {
    throw new HttpsError(
        "permission-denied", "You cannot delete this journal entry.");
  }

  const comments = await tripRef.collection("comments")
      .where("entryId", "==", entryId).limit(500).get();
  if (comments.size === 500) {
    throw new HttpsError(
        "resource-exhausted",
        "This entry has too many comments to delete safely. Contact support.",
    );
  }

  const imagePath = entry.get("imagePath");
  if (typeof imagePath === "string") {
    try {
      await storage.bucket().file(imagePath).delete({ignoreNotFound: true});
    } catch (error) {
      console.error("Entry photo cleanup failed", {tripId, entryId, error});
      throw new HttpsError(
          "internal", "The journal entry could not be deleted safely.");
    }
  }
  await Promise.all(comments.docs.map((comment) => comment.ref.delete()));
  await entryRef.delete();
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
  const userRef = db.collection("users").doc(userId);
  const [
    ownedTrips,
    authoredEntries,
    authoredSnippets,
    authoredComments,
    memberships,
    circleMirrors,
    incomingMirrors,
    outgoingMirrors,
    blockedMirrors,
    circleProfile,
  ] =
    await Promise.all([
      db.collection("trips").where("ownerId", "==", userId).get(),
      db.collectionGroup("entries").where("authorId", "==", userId).get(),
      db.collectionGroup("snippets").where("authorId", "==", userId).get(),
      db.collectionGroup("comments").where("authorId", "==", userId).get(),
      db.collectionGroup("members").where("userId", "==", userId).get(),
      db.collectionGroup("circle").where("userId", "==", userId).get(),
      db.collectionGroup("incomingRequests").where("userId", "==", userId).get(),
      db.collectionGroup("outgoingRequests").where("userId", "==", userId).get(),
      db.collectionGroup("blocked").where("userId", "==", userId).get(),
      db.collection("circleProfiles").doc(userId).get(),
    ]);

  try {
    await storage.bucket().deleteFiles({prefix: `users/${userId}/`});
    await Promise.all(authoredEntries.docs.map((entry) => entry.ref.delete()));
    await Promise.all(authoredSnippets.docs.map((snippet) => snippet.ref.delete()));
    await Promise.all(authoredComments.docs.map((comment) => comment.ref.delete()));
    const circleReferences = [
      ...circleMirrors.docs,
      ...incomingMirrors.docs,
      ...outgoingMirrors.docs,
      ...blockedMirrors.docs,
    ];
    await Promise.all(circleReferences.map((document) => document.ref.delete()));
    await Promise.all(ownedTrips.docs.map((trip) => db.recursiveDelete(trip.ref)));
    await Promise.all(memberships.docs.map((member) => member.ref.delete()));
    if (circleProfile.exists) {
      await db.collection("trekIds").doc(circleProfile.get("trekId")).delete();
      await circleProfile.ref.delete();
    }
    await db.recursiveDelete(userRef);
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
