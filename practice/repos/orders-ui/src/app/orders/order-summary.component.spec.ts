import { ComponentFixture, TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { OrderSummary } from './order-summary';
import { OrderSummaryComponent } from './order-summary.component';
import { OrderService } from './order.service';

describe('OrderSummaryComponent', () => {
  let fixture: ComponentFixture<OrderSummaryComponent>;
  let orderService: jasmine.SpyObj<OrderService>;

  const summary: OrderSummary = {
    orderId: 1001,
    itemCount: 2,
    subtotal: { amount: 45, currency: 'USD' },
    shipping: { amount: 7.99, currency: 'USD' },
    discount: { amount: 0, currency: 'USD' },
    total: { amount: 52.99, currency: 'USD' },
  };

  beforeEach(async () => {
    orderService = jasmine.createSpyObj<OrderService>('OrderService', ['getSummary']);
    await TestBed.configureTestingModule({
      imports: [OrderSummaryComponent],
      providers: [{ provide: OrderService, useValue: orderService }],
    }).compileComponents();
    fixture = TestBed.createComponent(OrderSummaryComponent);
    fixture.detectChanges();
  });

  async function loadOrder(id: number): Promise<HTMLElement> {
    const element: HTMLElement = fixture.nativeElement;
    const input = element.querySelector<HTMLInputElement>('[data-testid="order-id"]')!;
    input.value = String(id);
    input.dispatchEvent(new Event('input'));
    element.querySelector<HTMLButtonElement>('[data-testid="load-order"]')!.click();
    fixture.detectChanges();
    await fixture.whenStable();
    return element;
  }

  it('shows the totals for a found order', async () => {
    orderService.getSummary.and.returnValue(of(summary));

    const element = await loadOrder(1001);

    expect(orderService.getSummary).toHaveBeenCalledWith(1001);
    expect(element.querySelector('[data-testid="summary-total"]')?.textContent).toContain('52.99 USD');
  });

  it('shows an error when the order is not found', async () => {
    orderService.getSummary.and.returnValue(throwError(() => new Error('404')));

    const element = await loadOrder(42);

    expect(element.querySelector('[data-testid="order-error"]')?.textContent).toContain('Order 42 was not found.');
  });
});
