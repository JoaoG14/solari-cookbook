import { describe, expect, it } from 'vitest';

import {
  extractTaskResultArtifacts,
  extractTaskResultFileArtifacts
} from './taskResults';

describe('extractTaskResultFileArtifacts', () => {
  it('extracts output file citations and removes the raw directive', () => {
    expect(
      extractTaskResultFileArtifacts(
        'The editable slide deck is ready for review: :codex-file-citation{path="/tmp/onboarding-deck.pptx" purpose="output"}.'
      )
    ).toEqual({
      content: 'The editable slide deck is ready for review.',
      artifacts: [
        {
          type: 'file',
          path: '/tmp/onboarding-deck.pptx',
          label: 'onboarding-deck.pptx'
        }
      ]
    });
  });

  it('leaves source citations in the message', () => {
    const content =
      'Based on ::codex-file-citation{path="/tmp/source.pdf" purpose="source"}.';

    expect(extractTaskResultFileArtifacts(content)).toEqual({
      content,
      artifacts: []
    });
  });
});

describe('extractTaskResultArtifacts', () => {
  it('promotes a Google Slides link to an openable artifact', () => {
    expect(
      extractTaskResultArtifacts(
        'Rascunho pronto no [Google Slides](https://docs.google.com/presentation/d/deck-id/edit), com 10 slides.'
      )
    ).toEqual({
      content: 'Rascunho pronto no Google Slides, com 10 slides.',
      artifacts: [
        {
          type: 'link',
          url: 'https://docs.google.com/presentation/d/deck-id/edit',
          kind: 'slides',
          title: 'Google Slides'
        }
      ]
    });
  });
});
