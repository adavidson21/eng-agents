import { Component } from '@angular/core';

import { OrderSummaryComponent } from './orders/order-summary.component';

@Component({
  selector: 'app-root',
  imports: [OrderSummaryComponent],
  templateUrl: './app.component.html',
  styleUrl: './app.component.css',
})
export class AppComponent {}
