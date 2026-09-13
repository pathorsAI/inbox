/* eslint-disable no-bitwise */
import { remuxWebmToOgg } from './webmOpusToOgg';

const SEGMENT_ID = 0x18538067;
const CLUSTER_ID = 0x1f43b675;
const SIMPLE_BLOCK_ID = 0xa3;

const OPUS_FRAME_BYTES = 3;
const OGG_CAPTURE_PATTERN = [0x4f, 0x67, 0x67, 0x53];

// EBML element ids are written big-endian with their leading marker bits kept,
// exactly as the parser reads them back.
const idToBytes = id => {
  const bytes = [];
  let value = id;
  while (value > 0) {
    bytes.unshift(value & 0xff);
    value = Math.floor(value / 256);
  }
  return bytes;
};

// 0xff is the all-ones one-byte VINT — "unknown size", which is what
// MediaRecorder stamps on every Segment and Cluster it streams out.
const openMasterElement = id => [...idToBytes(id), 0xff];

const sizedElement = (id, payload) => [
  ...idToBytes(id),
  0x80 | payload.length,
  ...payload,
];

// Track number VINT, int16 relative timecode, flags byte, then the raw frame.
const simpleBlock = frame =>
  sizedElement(SIMPLE_BLOCK_ID, [0x81, 0, 0, 0x80, ...frame]);

// A WebM shaped the way MediaRecorder emits one: a single unknown-size Segment
// holding a long run of unknown-size Clusters, each carrying one Opus frame.
const streamingWebmBytes = clusterCount => {
  const bytes = [...openMasterElement(SEGMENT_ID)];
  for (let i = 0; i < clusterCount; i += 1) {
    bytes.push(...openMasterElement(CLUSTER_ID));
    // 0x78 is a 20 ms single-frame Opus TOC byte; the rest is filler payload.
    bytes.push(...simpleBlock([0x78, i & 0xff, 0x55]));
  }
  return new Uint8Array(bytes);
};

// jsdom's Blob has no arrayBuffer(), which is the only method the remuxer uses.
const blobLike = bytes => ({ arrayBuffer: async () => bytes.buffer });

const readBlob = blob =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(new Uint8Array(reader.result));
    reader.onerror = () => reject(reader.error);
    reader.readAsArrayBuffer(blob);
  });

// Walk the OGG pages and rebuild each packet's length from the lacing tables.
const oggPacketLengths = bytes => {
  const lengths = [];
  let pos = 0;
  while (pos < bytes.length) {
    const segmentCount = bytes[pos + 26];
    const segmentTable = bytes.slice(pos + 27, pos + 27 + segmentCount);
    let packetLength = 0;
    segmentTable.forEach(segment => {
      packetLength += segment;
      if (segment < 255) {
        lengths.push(packetLength);
        packetLength = 0;
      }
    });
    pos +=
      27 +
      segmentCount +
      segmentTable.reduce((total, segment) => total + segment, 0);
  }
  return lengths;
};

describe('remuxWebmToOgg', () => {
  it('returns an OGG input unchanged', async () => {
    const ogg = blobLike(new Uint8Array([...OGG_CAPTURE_PATTERN, 0x00]));

    await expect(remuxWebmToOgg(ogg)).resolves.toBe(ogg);
  });

  it('collects every frame from a long run of unknown-size clusters', async () => {
    // Descending into an unknown-size cluster with a recursive call nests one
    // frame per cluster; past this many the walker used to die with
    // "Maximum call stack size exceeded" instead of producing a file.
    const clusterCount = 100000;

    const result = await remuxWebmToOgg(
      blobLike(streamingWebmBytes(clusterCount))
    );
    const bytes = await readBlob(result);

    expect(result.type).toBe('audio/ogg');
    expect(Array.from(bytes.slice(0, 4))).toEqual(OGG_CAPTURE_PATTERN);

    // OpusHead and OpusTags, then exactly one packet per cluster.
    const packetLengths = oggPacketLengths(bytes);
    expect(packetLengths).toHaveLength(clusterCount + 2);
    expect(packetLengths.slice(2)).toEqual(
      Array(clusterCount).fill(OPUS_FRAME_BYTES)
    );
  });

  it('throws when the input carries no Opus frames', async () => {
    const empty = blobLike(new Uint8Array(openMasterElement(SEGMENT_ID)));

    await expect(remuxWebmToOgg(empty)).rejects.toThrow(
      'No Opus frames found in WebM input'
    );
  });
});
