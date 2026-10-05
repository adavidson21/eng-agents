import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { formatMoney } from './money';
import { OrderSummary } from './order-summary';
import { OrderService } from './order.service';

@Component({
  selector: 'app-order-summary',
  imports: [FormsModule],
  templateUrl: './order-summary.component.html',
  styleUrl: './order-summary.component.css',
})
export class OrderSummaryComponent {
  private readonly orders = inject(OrderService);

  protected orderId: number | null = null;
  protected readonly summary = signal<OrderSummary | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly formatMoney = formatMoney;

  protected load(): void {
    if (this.orderId === null) {
      return;
    }

    this.summary.set(null);
    this.error.set(null);
    this.orders.getSummary(this.orderId).subscribe({
      next: (summary) => this.summary.set(summary),
      error: () => this.error.set(`Order ${this.orderId} was not found.`),
    });
  }
}
