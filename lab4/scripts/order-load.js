import http from 'k6/http';
import { check } from 'k6';
export const options = {
  scenarios: {
    orders: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 5),
      timeUnit: '1s',
      duration: __ENV.DURATION || '2h',
      preAllocatedVUs: 10,
      maxVUs: 30,
    },
  },
};
export default function () {
  const response = http.post(`${__ENV.BASE_URL || 'http://127.0.0.1:8080'}/order`,
    JSON.stringify({ item: 'lab4-load', quantity: 1 }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '5s' });
  check(response, { 'order created (201)': r => r.status === 201 });
}
