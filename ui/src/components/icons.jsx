const I = (d) => (props) => (
  <svg viewBox="0 0 24 24" {...props}>{d}</svg>
);
export const IconBack = I(<path d="M15 6l-6 6 6 6" />);
export const IconForward = I(<path d="M9 6l6 6-6 6" />);
export const IconReload = I(<><path d="M20 11a8 8 0 1 0-2.3 5.7" /><path d="M20 4v7h-7" /></>);
export const IconPanel = I(<><rect x="3" y="4" width="18" height="16" rx="2" /><path d="M15 4v16" /></>);
export const IconCode = I(<path d="M9 8l-4 4 4 4M15 8l4 4-4 4" />);
export const IconPlus = I(<path d="M12 5v14M5 12h14" />);
export const IconClose = I(<path d="M6 6l12 12M18 6L6 18" />);
export const IconUp = I(<path d="M6 15l6-6 6 6" />);
export const IconDown = I(<path d="M6 9l6 6 6-6" />);
export const IconLeft = I(<path d="M15 6l-6 6 6 6" />);
export const IconRight = I(<path d="M9 6l6 6-6 6" />);
