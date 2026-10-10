// xcnav_avatar_service (AWS Lambda, us-west-1, behind the xcnav_avatar_api HTTP API)
//
// GET  ?pilot_id=<id>                      -> { pilot_id, avatar: <base64 jpg> }
// POST { pilot_id, avatar: <base64 jpg> }  -> stores avatars/<pilot_id>.jpg
//
// Every request must carry an "authorizationToken" header matching the AUTH_TOKEN
// environment variable (the app's profileStoreToken in lib/secrets.dart).
//
// Deploy: see deploy.sh next to this file.

import { timingSafeEqual } from "node:crypto";
import { GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand } from "@aws-sdk/lib-dynamodb";

const BUCKET = "xcnavappavatars";
// Avatars are compressed to ~128px in the app; this is generous headroom.
const MAX_AVATAR_BYTES = 512 * 1024;

const db = DynamoDBDocumentClient.from(new DynamoDBClient({ region: "us-west-1" }));
const s3 = new S3Client({ region: "us-west-1" });

function reply(statusCode, body) {
    return {
        statusCode,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        isBase64Encoded: false,
    };
}

function isAuthorized(event) {
    const expected = process.env.AUTH_TOKEN;
    if (!expected) {
        console.error("AUTH_TOKEN is not configured; rejecting all requests");
        return false;
    }
    // HTTP API (payload v2) lowercases header names.
    const given = event.headers?.authorizationtoken ?? "";
    const a = Buffer.from(given);
    const b = Buffer.from(expected);
    return a.length === b.length && timingSafeEqual(a, b);
}

function validPilotId(pilot_id) {
    return typeof pilot_id === "string" && /^[a-z0-9_-]{1,64}$/.test(pilot_id);
}

function avatarKey(pilot_id) {
    return "avatars/" + pilot_id + ".jpg";
}

async function getAvatar(event) {
    const pilot_id = event.queryStringParameters?.pilot_id?.toLowerCase();
    if (!validPilotId(pilot_id)) return reply(400, { error: "invalid pilot_id" });

    try {
        const result = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: avatarKey(pilot_id) }));
        const bytes = await result.Body.transformToByteArray();
        return reply(200, { pilot_id, avatar: Buffer.from(bytes).toString("base64") });
    } catch (err) {
        if (err.name === "NoSuchKey") return reply(404, { error: "no avatar", pilot_id });
        throw err;
    }
}

async function putAvatar(event) {
    let msg;
    try {
        msg = JSON.parse(event.isBase64Encoded ? Buffer.from(event.body, "base64").toString() : event.body);
    } catch {
        return reply(400, { error: "invalid json" });
    }

    const pilot_id = typeof msg?.pilot_id === "string" ? msg.pilot_id.toLowerCase() : undefined;
    if (!validPilotId(pilot_id)) return reply(400, { error: "invalid pilot_id" });
    if (typeof msg.avatar !== "string" || msg.avatar.length === 0) return reply(400, { error: "missing avatar" });

    const image = Buffer.from(msg.avatar, "base64");
    if (image.length === 0 || image.length > MAX_AVATAR_BYTES) return reply(413, { error: "avatar size out of range" });

    const pilot = await db.send(new GetCommand({ TableName: "Pilots", Key: { id: pilot_id } }));
    if (pilot.Item === undefined) return reply(404, { error: "unknown pilot", pilot_id });

    await s3.send(
        new PutObjectCommand({ Bucket: BUCKET, Key: avatarKey(pilot_id), Body: image, ContentType: "image/jpeg" })
    );
    console.log("Stored avatar", pilot_id, image.length, "bytes");
    return reply(200, { pilot_id });
}

export const handler = async (event) => {
    if (!isAuthorized(event)) return reply(401, { error: "unauthorized" });

    switch (event.requestContext?.http?.method) {
        case "GET":
            return getAvatar(event);
        case "POST":
            return putAvatar(event);
        default:
            return reply(405, { error: "method not allowed" });
    }
};
