import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 5,
  duration: '3m',
};

const baseUrl = __ENV.BASE_URL || 'http://127.0.0.1:8080';

export default function () {
  const payload = JSON.stringify({
    item: 'book',
    quantity: 1,
  });

  const response = http.post(`${baseUrl}/order`, payload, {
    headers: {
      'Content-Type': 'application/json',
    },
  });

  check(response, {
    'order created': (result) => result.status === 201,
  });

  sleep(0.2);
}
