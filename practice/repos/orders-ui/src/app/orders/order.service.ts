import { HttpClient } from '@angular/common/http';
import { inject, Injectable } from '@angular/core';
import { Observable } from 'rxjs';

import { API_BASE_URL } from '../api-config';
import { OrderSummary } from './order-summary';

@Injectable({ providedIn: 'root' })
export class OrderService {
  private readonly http = inject(HttpClient);

  getSummary(orderId: number): Observable<OrderSummary> {
    return this.http.get<OrderSummary>(`${API_BASE_URL}/api/orders/${orderId}/summary`);
  }
}
