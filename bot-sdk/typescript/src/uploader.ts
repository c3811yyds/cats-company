// FileUploader — HTTP multipart upload to Cats Company server.

import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import type { UploadResult } from './types';
import { UploadError } from './errors';

export class FileUploader {
  private readonly httpBaseUrl: string;
  private readonly apiKey: string;

  constructor(httpBaseUrl: string, apiKey: string) {
    this.httpBaseUrl = httpBaseUrl.replace(/\/$/, '');
    this.apiKey = apiKey;
  }

  /**
   * Upload a file from disk.
   */
  async upload(filePath: string, type: 'image' | 'file' = 'file'): Promise<UploadResult> {
    const buffer = fs.readFileSync(filePath);
    const filename = path.basename(filePath);
    return this.uploadBuffer(buffer, filename, type);
  }

  /**
   * Upload a buffer with a given filename.
   */
  async uploadBuffer(
    buffer: Buffer,
    filename: string,
    type: 'image' | 'file' = 'file',
  ): Promise<UploadResult> {
    const url = `${this.httpBaseUrl}/api/upload?type=${type}`;

    // Build multipart/form-data body manually for maximum compatibility
    const boundary = `----CatsBotBoundary${crypto.randomBytes(16).toString('hex')}`;
    const header = Buffer.from(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
      `Content-Type: application/octet-stream\r\n\r\n`,
    );
    const footer = Buffer.from(`\r\n--${boundary}--\r\n`);
    const body = Buffer.concat([header, buffer, footer]);

    let res: Response;
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `ApiKey ${this.apiKey}`,
          'Content-Type': `multipart/form-data; boundary=${boundary}`,
        },
        body,
      });
    } catch (err: any) {
      throw new UploadError(`Upload request failed: ${err.message}`);
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new UploadError(`Upload failed (${res.status}): ${text}`, res.status);
    }

    return (await res.json()) as UploadResult;
  }
}
