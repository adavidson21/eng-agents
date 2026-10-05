import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';

import { AppComponent } from './app.component';

describe('AppComponent', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [AppComponent],
      providers: [provideHttpClient(), provideHttpClientTesting()],
    }).compileComponents();
  });

  it('renders the page heading', () => {
    const fixture = TestBed.createComponent(AppComponent);
    fixture.detectChanges();
    expect((fixture.nativeElement as HTMLElement).querySelector('h1')?.textContent).toContain('Orders');
  });
});
