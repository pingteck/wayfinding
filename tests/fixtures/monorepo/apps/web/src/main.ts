interface AppConfig {
  title: string;
}

export function mount(root: HTMLElement, config: AppConfig): void {
  root.textContent = config.title;
}
