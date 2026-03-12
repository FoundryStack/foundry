declare module 'cytoscape-node-html-label' {
  import type { Core } from 'cytoscape';
  function nodeHtmlLabel(cytoscape: typeof import('cytoscape')): void;
  export default nodeHtmlLabel;
}
