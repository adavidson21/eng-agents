import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';

import { API_BASE_URL } from '../api-config';
import { OrderSummary } from './order-summary';
import { OrderService } from './order.service';

describe('OrderService', () => {
  let service: OrderService;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    service = TestBed.inject(OrderService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('gets the summary for an order', () => {
    const summary: OrderSummary = {
      orderId: 1001,
      itemCount: 2,
      subtotal: { amount: 45, currency: 'USD' },
      shipping: { amount: 7.99, currency: 'USD' },
      discount: { amount: 0, currency: 'USD' },
      total: { amount: 52.99, currency: 'USD' },
    };
    let result: OrderSummary | undefined;

    service.getSummary(1001).subscribe((value) => (result = value));
    http.expectOne(`${API_BASE_URL}/api/orders/1001/summary`).flush(summary);

    expect(result).toEqual(summary);
  });
});
