import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 5,
  duration: '3m',
};

export default function () {
  const payload = JSON.stringify({
    item: 'load-test-item',
    quantity: 1,
  });

  const write = http.post('http://localhost:8080/order', payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  check(write, {
    'order created': (r) => r.status === 201,
  });

  const read = http.get('http://localhost:8080/orders');

  check(read, {
    'orders loaded': (r) => r.status === 200,
  });

  sleep(1);
}