/**
 * CloudWatch Synthetics Heartbeat Canary
 * Runtime: syn-nodejs-puppeteer-9.1
 *
 * 每 5 分鐘呼叫 API 根路徑，驗證回傳 200。
 * 失敗時 Synthetics 自動記錄 CloudWatch Metric: SuccessPercent = 0
 * 可在 CloudWatch Alarm 中監控此 metric 並發送通知。
 */
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const API_URL = process.env.API_URL;

exports.handler = async () => {
  const parsedUrl = new URL(API_URL);

  const requestOptions = {
    hostname: parsedUrl.hostname,
    method: 'GET',
    path: '/',
    protocol: 'https:',
    port: 443,
  };

  await synthetics.executeHttpStep(
    'GET / - Verify API responds 200',
    requestOptions,
    async function verifyResponse(res) {
      return new Promise((resolve, reject) => {
        log.info(`Response status: ${res.statusCode}`);

        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(`Expected 2xx, got ${res.statusCode}`));
          return;
        }

        // 消耗 response body（避免連線 hang）
        res.resume();
        resolve();
      });
    }
  );
};
