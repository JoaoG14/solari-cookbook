import { Solari, type BrowserSession } from '@solarisdk/browser';
import { z } from 'zod';
import { CloudError } from './cloudCommands';
import type { CloudJob } from './cloudStore';

export const browserActionSchema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('open'), url: z.url().max(4000) }),
  z.object({ action: z.literal('read') }),
  z.object({ action: z.literal('click'), role: z.enum(['link', 'button', 'tab', 'checkbox', 'radio', 'menuitem']), name: z.string().max(500) }),
  z.object({ action: z.literal('fill'), label: z.string().max(500), value: z.string().max(4000) }),
  z.object({ action: z.literal('press'), key: z.enum(['Enter', 'Tab', 'Escape', 'ArrowDown', 'ArrowUp']) }),
  z.object({ action: z.literal('scroll'), direction: z.enum(['up', 'down']) })
]);

type Page = Awaited<ReturnType<BrowserSession['newPage']>>;
type CDPSession = Awaited<ReturnType<ReturnType<Page['context']>['newCDPSession']>>;
export type BrowserStreamEvent = BrowserPreview | { status: 'inactive' | 'error' | 'heartbeat' };
type Session = { client: Pick<Solari, 'close'>; browser: Pick<BrowserSession, 'close'>; page: Page };
type Entry = {
  job: CloudJob;
  session: Promise<Session>;
  queue: Promise<unknown>;
  frame?: BrowserPreview;
  capture?: Promise<BrowserPreview>;
  closing?: Promise<void>;
  viewers: Set<(frame: BrowserStreamEvent) => void>;
  streamQueue: Promise<void>;
  cdp?: CDPSession;
  streamFrame?: BrowserPreview;
  title?: string;
};
export type BrowserPreview = {
  status: 'active';
  url: string;
  title: string;
  image: string;
  capturedAt: string;
};

// Sessions and frames live only in this API process. Run one API/worker instance.
export class CloudBrowser {
  private readonly entries = new Map<string, Entry>();
  readonly configured: boolean;

  constructor(
    apiKey?: string,
    private readonly createClient: () => Pick<Solari, 'launch' | 'close'> = () =>
      new Solari({ apiKey: apiKey!, timeoutMs: 30_000, maxAttempts: 1 })
  ) {
    this.configured = Boolean(apiKey);
  }

  private async launch(): Promise<Session> {
    const client = this.createClient();
    let browser: BrowserSession | undefined;
    try {
      browser = await client.launch();
      const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, acceptDownloads: false });
      const page = await context.newPage();
      page.setDefaultTimeout(10_000);
      page.setDefaultNavigationTimeout(30_000);
      return { client, browser, page };
    } catch {
      try { await browser?.close(); } finally { await client.close(); }
      throw new CloudError(503, 'The cloud browser could not start. Try again later.');
    }
  }

  async act(job: CloudJob, input: z.infer<typeof browserActionSchema>, signal: AbortSignal) {
    signal.throwIfAborted();
    if (!this.configured) throw new CloudError(503, 'The cloud browser is not configured.');
    if (input.action === 'open') {
      const url = new URL(input.url);
      if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password)
        throw new CloudError(400, 'Open an HTTP or HTTPS page without embedded credentials.');
    }
    const key = this.key(job);
    let entry = this.entries.get(key);
    if (!entry) {
      if (input.action !== 'open') return { error: 'Open a page first. Each new or resumed run starts with a fresh browser.' };
      entry = { job, session: this.launch(), queue: Promise.resolve(), viewers: new Set(), streamQueue: Promise.resolve() };
      this.entries.set(key, entry);
    }
    const current = entry;
    const operation = current.queue.then(async () => {
      const { page } = await current.session;
      signal.throwIfAborted();
      switch (input.action) {
        case 'open': await page.goto(input.url, { waitUntil: 'domcontentloaded' }); break;
        case 'click': await page.getByRole(input.role, { name: input.name, exact: true }).click(); break;
        case 'fill': await page.getByLabel(input.label, { exact: true }).fill(input.value); break;
        case 'press': await page.keyboard.press(input.key); break;
        case 'scroll': await page.mouse.wheel(0, input.direction === 'down' ? 600 : -600); break;
      }
      signal.throwIfAborted();
      current.title = await page.title();
      if (current.streamFrame) {
        current.streamFrame = { ...current.streamFrame, title: current.title, url: page.url() };
        for (const viewer of current.viewers) viewer(current.streamFrame);
      }
      return { url: page.url(), title: current.title, content: (await page.locator('body').ariaSnapshot()).slice(0, 24_000) };
    });
    current.queue = operation.catch(() => undefined);
    try {
      return await operation;
    } catch {
      signal.throwIfAborted();
      // Playwright errors may contain authenticated CDP URLs. Never return them.
      return { error: 'The browser action failed. Read the page again or open its URL and retry. Use exact names and labels from the page. Login, downloads, and browser takeover are unavailable.' };
    }
  }

  activeJob(userId: string, threadId: string): CloudJob | undefined {
    return [...this.entries.values()].find(({ job, closing }) => !closing && job.user_id === userId && job.thread_id === threadId)?.job;
  }

  async preview(job: CloudJob): Promise<BrowserPreview | { status: 'inactive' }> {
    const entry = this.entries.get(this.key(job));
    if (!entry) return { status: 'inactive' };
    if (entry.frame && Date.now() - Date.parse(entry.frame.capturedAt) < 1000) return entry.frame;
    if (entry.capture) return entry.capture;
    entry.capture = (async () => {
      const { page } = await entry.session;
      const image = await page.screenshot({ type: 'jpeg', quality: 65, timeout: 5000 });
      const frame: BrowserPreview = {
        status: 'active', url: page.url(), title: await page.title(),
        image: image.toString('base64'), capturedAt: new Date().toISOString()
      };
      entry.frame = frame;
      return frame;
    })();
    try { return await entry.capture; }
    catch { throw new CloudError(503, 'Browser preview is temporarily unavailable.'); }
    finally { delete entry.capture; }
  }

  async watch(job: CloudJob, receive: (frame: BrowserStreamEvent) => void): Promise<() => Promise<void>> {
    const entry = this.entries.get(this.key(job));
    if (!entry || entry.closing) {
      receive({ status: 'inactive' });
      return async () => {};
    }
    entry.viewers.add(receive);
    try {
      await this.syncStream(entry);
      if (entry.streamFrame) receive(entry.streamFrame);
    } catch {
      entry.viewers.delete(receive);
      await this.syncStream(entry).catch(() => {});
      throw new CloudError(503, 'Browser streaming is temporarily unavailable.');
    }
    return async () => {
      entry.viewers.delete(receive);
      await this.syncStream(entry);
    };
  }

  private syncStream(entry: Entry): Promise<void> {
    // Serialize subscribe/unsubscribe so a retiring viewer cannot stop a new stream.
    entry.streamQueue = entry.streamQueue.catch(() => {}).then(async () => {
      if (!entry.viewers.size || entry.closing) {
        const cdp = entry.cdp;
        delete entry.cdp;
        delete entry.streamFrame;
        if (cdp) {
          try { await cdp.send('Page.stopScreencast'); }
          finally { await cdp.detach().catch(() => {}); }
        }
        return;
      }
      if (entry.cdp) return;
      const { page } = await entry.session;
      if (!entry.viewers.size || entry.closing) return;
      const cdp = await page.context().newCDPSession(page);
      entry.cdp = cdp;
      cdp.on('close', () => {
        if (entry.cdp !== cdp || entry.closing) return;
        delete entry.cdp;
        delete entry.streamFrame;
        for (const viewer of entry.viewers) viewer({ status: 'error' });
      });
      cdp.on('Page.screencastFrame', ({ data, sessionId }) => {
        void cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {
          if (entry.cdp !== cdp || entry.closing) return;
          for (const viewer of entry.viewers) viewer({ status: 'error' });
        });
        if (entry.closing || entry.cdp !== cdp) return;
        entry.streamFrame = {
          status: 'active', image: data, url: page.url(), title: entry.title ?? 'Browser',
          capturedAt: new Date().toISOString()
        };
        for (const viewer of entry.viewers) viewer(entry.streamFrame);
      });
      try {
        await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 65, maxWidth: 1280, maxHeight: 800 });
      } catch (error) {
        delete entry.cdp;
        await cdp.detach().catch(() => {});
        throw error;
      }
    });
    return entry.streamQueue;
  }

  async close(job: CloudJob) {
    const key = this.key(job);
    const entry = this.entries.get(key);
    if (!entry) return;
    if (entry.closing) return entry.closing;
    for (const viewer of entry.viewers) viewer({ status: 'inactive' });
    entry.viewers.clear();
    entry.closing = (async () => {
      await this.syncStream(entry).catch(() => {});
      try {
        const { browser, client } = await entry.session;
        try { await browser.close(); } finally { await client.close(); }
      } catch {
        console.error('Cloud browser cleanup failed. The Solari session deadline remains the fallback.');
      } finally {
        this.entries.delete(key);
      }
    })();
    return entry.closing;
  }

  async closeAll() {
    await Promise.all([...this.entries.values()].map(({ job }) => this.close(job)));
  }

  private key(job: CloudJob) { return `${job.id}:${job.lease}`; }
}
