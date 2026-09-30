import type { NativeAgentLocalToolName } from './nativeAgent';

export type OpenAIFunctionToolDefinition = {
  type: 'function';
  name: NativeAgentLocalToolName;
  description: string;
  parameters: {
    type: 'object';
    properties: Record<string, unknown>;
    required: string[];
    additionalProperties: false;
  };
  strict: true;
};

export const localToolDescriptions: Record<
  NativeAgentLocalToolName,
  OpenAIFunctionToolDefinition
> = {
  filesystem_list_directory: {
    type: 'function',
    name: 'filesystem_list_directory',
    description:
      "List files and folders on the user's local filesystem. Relative paths resolve from the agent working directory. Use ~/Desktop, ~/Downloads, or ~/Documents when the user names one of those standard macOS folders.",
    parameters: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description:
            'Directory path to list. Use ~/Desktop, ~/Downloads, or ~/Documents for those named personal folders. Use "." only for the agent working directory.'
        }
      },
      required: ['path'],
      additionalProperties: false
    },
    strict: true
  },
  filesystem_read_text_file: {
    type: 'function',
    name: 'filesystem_read_text_file',
    description:
      "Read a UTF-8 text file from the user's local filesystem. Use only when file contents are needed.",
    parameters: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description:
            'File path to read. Use relative paths from the agent working directory unless the user gave an absolute path.'
        }
      },
      required: ['path'],
      additionalProperties: false
    },
    strict: true
  },
  filesystem_create_directory: {
    type: 'function',
    name: 'filesystem_create_directory',
    description: "Create a directory on the user's local filesystem.",
    parameters: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description:
            'Directory path to create. Use relative paths from the agent working directory unless the user gave an absolute path.'
        }
      },
      required: ['path'],
      additionalProperties: false
    },
    strict: true
  },
  filesystem_move_file: {
    type: 'function',
    name: 'filesystem_move_file',
    description: "Move or rename one file on the user's local filesystem.",
    parameters: {
      type: 'object',
      properties: {
        sourcePath: {
          type: 'string',
          description:
            'Existing file path to move. Use relative paths from the agent working directory unless the user gave an absolute path.'
        },
        destinationPath: {
          type: 'string',
          description:
            'Destination file path. Use relative paths from the agent working directory unless the user gave an absolute path.'
        }
      },
      required: ['sourcePath', 'destinationPath'],
      additionalProperties: false
    },
    strict: true
  },
  filesystem_write_text_file: {
    type: 'function',
    name: 'filesystem_write_text_file',
    description: "Create a UTF-8 text file on the user's local filesystem.",
    parameters: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description:
            'File path to create. Use relative paths from the agent working directory unless the user gave an absolute path.'
        },
        content: {
          type: 'string',
          description: 'UTF-8 text content to write.'
        }
      },
      required: ['path', 'content'],
      additionalProperties: false
    },
    strict: true
  },
  memory_search: {
    type: 'function',
    name: 'memory_search',
    description:
      'Search the active Dony CONTEXT.md for durable user and project context. Returns a bounded excerpt and its exact Markdown path.',
    parameters: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Specific text to find.' }
      },
      required: ['query'],
      additionalProperties: false
    },
    strict: true
  },
  memory_read: {
    type: 'function',
    name: 'memory_read',
    description: 'Read the active Dony CONTEXT.md file.',
    parameters: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          enum: ['CONTEXT.md'],
          description: 'The canonical user context path.'
        }
      },
      required: ['path'],
      additionalProperties: false
    },
    strict: true
  },
  memory_write: {
    type: 'function',
    name: 'memory_write',
    description:
      'Save a complete replacement for CONTEXT.md to persist durable, well-supported user context.',
    parameters: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          enum: ['CONTEXT.md'],
          description: 'The canonical user context path.'
        },
        content: {
          type: 'string',
          description: 'Complete replacement Markdown content.'
        },
        reason: {
          type: 'string',
          description: 'Short provenance-oriented reason for the update.'
        }
      },
      required: ['path', 'content', 'reason'],
      additionalProperties: false
    },
    strict: true
  },
  chat_search: {
    type: 'function',
    name: 'chat_search',
    description:
      'Search bounded excerpts from visible Dony chat history when an earlier conversation is relevant.',
    parameters: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Specific text to find.' },
        scope: {
          type: 'string',
          enum: ['current_agent', 'all_agents'],
          description: 'Search this agent by default or all agents when needed.'
        },
        role: {
          type: 'string',
          enum: ['any', 'user', 'assistant'],
          description: 'Optional message-role filter.'
        },
        from: {
          type: ['string', 'null'],
          description: 'Optional inclusive ISO date or timestamp.'
        },
        to: {
          type: ['string', 'null'],
          description: 'Optional inclusive ISO date or timestamp.'
        },
        limit: {
          type: 'integer',
          minimum: 1,
          maximum: 20,
          description: 'Maximum number of matches.'
        }
      },
      required: ['query', 'scope', 'role', 'from', 'to', 'limit'],
      additionalProperties: false
    },
    strict: true
  },
  chat_read: {
    type: 'function',
    name: 'chat_read',
    description:
      'Read a small visible conversation window around one chat_search result.',
    parameters: {
      type: 'object',
      properties: {
        messageId: {
          type: 'string',
          description: 'Message ID returned by chat_search.'
        },
        scope: {
          type: 'string',
          enum: ['current_agent', 'all_agents'],
          description: 'Must allow the conversation that was searched.'
        },
        radius: {
          type: 'integer',
          minimum: 1,
          maximum: 10,
          description: 'Messages to include before and after the match.'
        }
      },
      required: ['messageId', 'scope', 'radius'],
      additionalProperties: false
    },
    strict: true
  },
  browser: {
    type: 'function',
    name: 'browser',
    description:
      'Control the browser selected in Dony Settings. Always start with ["help"] to discover the backend. Cua automatically opens a dedicated Chrome window using the user’s existing profile when needed: call ["get_browser_state"] to open/connect and list tabs (no user window selection needed), then ["get_browser_state", "{\"tab_id\":\"...\"}"] for a snapshot. Commands are a tool name and optional JSON argument string. Read fresh state after each action and verify its effect. Never blindly replay an uncertain action. For the legacy Dony browser, use agent-browser commands. Set requires_confirmation with an intent before sending, publishing, purchasing, deleting, submitting credentials, or changing account/security settings.',
    parameters: {
      type: 'object',
      properties: {
        command: {
          type: 'array',
          items: { type: 'string' },
          description:
            'Start with ["help"]. Cua examples: ["get_browser_state"] or ["browser_navigate", "{\"tab_id\":\"...\",\"url\":\"https://example.com\"}"]. Legacy Dony examples: ["snapshot", "-i"] or ["click", "@e3"].'
        },
        intent: {
          type: ['string', 'null'],
          description:
            'Brief description of a sensitive action for user confirmation.'
        },
        requires_confirmation: {
          type: ['boolean', 'null'],
          description: 'Request confirmation before consequential actions.'
        }
      },
      required: ['command', 'intent', 'requires_confirmation'],
      additionalProperties: false
    },
    strict: true
  },
  computer_use: {
    type: 'function',
    name: 'computer_use',
    description:
      'Use Dony Computer Use to observe or control the macOS desktop with an existing-window-first approach. Start with list_windows and get_window_state. Prefer fresh element_token targets; element_index requires its snapshot_id. Always include pid and window_id for element actions. Use background delivery by default; foreground is an explicit choice that can change focus. Reobserve after each mutation or uncertain result and verify the intended change before claiming success. Never blindly replay a timed-out action.',
    parameters: {
      type: 'object',
      properties: {
        action: {
          type: 'string',
          enum: [
            'check_permissions',
            'list_apps',
            'list_windows',
            'get_window_state',
            'get_screen_size',
            'get_cursor_position',
            'get_accessibility_tree',
            'launch_app',
            'kill_app',
            'click',
            'double_click',
            'right_click',
            'drag',
            'type_text',
            'press_key',
            'hotkey',
            'set_value',
            'scroll',
            'move_cursor',
            'zoom',
            'page',
            'start_recording',
            'stop_recording'
          ],
          description:
            'Driver action to run. Start with list_windows and get_window_state. Use launch_app only when no suitable existing window/app is available. Prefer pid, window_id, and a fresh element_token for element actions.'
        },
        pid: {
          type: ['number', 'null'],
          description:
            'Target process id returned by launch_app or list_windows.'
        },
        window_id: {
          type: ['integer', 'string', 'null'],
          pattern: '^[0-9]+$',
          description:
            'Exact target window id returned by list_windows. Preserve decimal strings without converting them to numbers.'
        },
        element_index: {
          type: ['number', 'null'],
          description:
            'Element index from the latest get_window_state result. Requires its matching snapshot_id. Prefer element_token.'
        },
        element_token: {
          type: ['string', 'null'],
          description:
            'Opaque element handle from the latest snapshot of this exact window. Refresh after an action or stale-token error.'
        },
        snapshot_id: {
          type: ['string', 'null'],
          description:
            'Snapshot identity returned by get_window_state; required with element_index.'
        },
        delivery_mode: {
          type: ['string', 'null'],
          enum: ['background', 'foreground', null],
          description:
            'Defaults to background. Foreground may change focus; do not automatically use it when background delivery fails.'
        },
        include_screenshot: {
          type: ['boolean', 'null'],
          description:
            'Whether get_window_state returns an image. Set false for a tree-only refresh.'
        },
        include_accessibility_tree: {
          type: ['boolean', 'null'],
          description:
            'Whether get_window_state returns the accessibility tree. Set false for screenshot-only capture.'
        },
        max_dimension: {
          type: ['integer', 'null'],
          minimum: 1,
          description:
            'Maximum screenshot edge in pixels. Use coordinates from the returned image without rescaling them.'
        },
        max_elements: {
          type: ['integer', 'null'],
          minimum: 1,
          description:
            'Maximum accessibility elements to capture. A truncated tree cannot prove that an element is absent.'
        },
        max_depth: {
          type: ['integer', 'null'],
          minimum: 1,
          description: 'Maximum accessibility-tree depth.'
        },
        direction: {
          type: ['string', 'null'],
          enum: ['up', 'down', 'left', 'right', null],
          description: 'Direction for scroll.'
        },
        amount: {
          type: ['integer', 'null'],
          minimum: 1,
          maximum: 50,
          description: 'Scroll wheel notches or keystroke repetitions.'
        },
        by: {
          type: ['string', 'null'],
          enum: ['line', 'page', null],
          description: 'Scroll granularity.'
        },
        x: {
          type: ['number', 'null'],
          description: 'Window-local screenshot X coordinate for pixel actions.'
        },
        y: {
          type: ['number', 'null'],
          description: 'Window-local screenshot Y coordinate for pixel actions.'
        },
        from_x: {
          type: ['number', 'null'],
          description: 'Drag start X coordinate.'
        },
        from_y: {
          type: ['number', 'null'],
          description: 'Drag start Y coordinate.'
        },
        to_x: {
          type: ['number', 'null'],
          description: 'Drag end X coordinate.'
        },
        to_y: {
          type: ['number', 'null'],
          description: 'Drag end Y coordinate.'
        },
        text: {
          type: ['string', 'null'],
          description: 'Text for type_text.'
        },
        value: {
          type: ['string', 'null'],
          description: 'Value for set_value.'
        },
        key: {
          type: ['string', 'null'],
          description: 'Key for press_key.'
        },
        keys: {
          anyOf: [
            {
              type: 'array',
              items: { type: 'string' }
            },
            { type: 'null' }
          ],
          description: 'Keys for hotkey, such as ["cmd", "space"].'
        },
        modifiers: {
          anyOf: [
            {
              type: 'array',
              items: { type: 'string' }
            },
            { type: 'null' }
          ],
          description: 'Modifier keys for press_key or pointer actions.'
        },
        bundle_id: {
          type: ['string', 'null'],
          description:
            'macOS bundle id for launch_app, such as com.apple.finder.'
        },
        name: {
          type: ['string', 'null'],
          description:
            'Application name for launch_app when bundle_id is unknown.'
        },
        urls: {
          anyOf: [
            {
              type: 'array',
              items: { type: 'string' }
            },
            { type: 'null' }
          ],
          description:
            'Optional URLs to pass to launch_app. Use only when launching is necessary; do not open duplicate browser tabs if an existing window can be reused.'
        },
        query: {
          type: ['string', 'null'],
          description:
            'Optional get_window_state filter query. Use it to narrow the window tree to relevant tabs, buttons, fields, or media controls.'
        },
        prompt: {
          type: ['boolean', 'null'],
          description:
            'Whether check_permissions should raise missing TCC prompts.'
        },
        intent: {
          type: ['string', 'null'],
          description:
            'Short plain-language description of a sensitive action for user confirmation.'
        },
        requires_confirmation: {
          type: ['boolean', 'null'],
          description:
            'Set true before an action that sends, publishes, purchases, deletes, changes security, installs software, grants access, or submits credentials.'
        }
      },
      required: [
        'action',
        'pid',
        'window_id',
        'element_index',
        'element_token',
        'snapshot_id',
        'delivery_mode',
        'include_screenshot',
        'include_accessibility_tree',
        'max_dimension',
        'max_elements',
        'max_depth',
        'direction',
        'amount',
        'by',
        'x',
        'y',
        'from_x',
        'from_y',
        'to_x',
        'to_y',
        'text',
        'value',
        'key',
        'keys',
        'modifiers',
        'bundle_id',
        'name',
        'urls',
        'query',
        'prompt',
        'intent',
        'requires_confirmation'
      ],
      additionalProperties: false
    },
    strict: true
  },
  connector_use: {
    type: 'function',
    name: 'connector_use',
    description:
      'Use backend-managed Composio connectors for authenticated cloud apps. Prefer this over computer_use whenever a matching plugin is available.',
    parameters: {
      type: 'object',
      properties: {
        action: {
          type: 'string',
          enum: [
            'list_toolkits',
            'search_tools',
            'execute_tool',
            'authorize_toolkit'
          ],
          description:
            'list_toolkits checks connection state, search_tools finds the right Composio tool, execute_tool runs a known tool slug, and authorize_toolkit creates a Connect Link.'
        },
        toolkit: {
          type: ['string', 'null'],
          description:
            'Optional toolkit slug returned by list_toolkits, such as gmail, outlook, slack, notion, or vercel. Required for authorize_toolkit.'
        },
        query: {
          type: ['string', 'null'],
          description: 'Natural-language tool search query for search_tools.'
        },
        toolSlug: {
          type: ['string', 'null'],
          description:
            'Composio tool slug to execute, such as GMAIL_FETCH_EMAILS or GOOGLEDRIVE_SEARCH_FILES.'
        },
        argumentsJson: {
          type: ['string', 'null'],
          description:
            'JSON object string containing arguments for execute_tool, or null when no arguments are needed.'
        },
        localFiles: {
          type: ['array', 'null'],
          description:
            'Local files Dony should stage before execute_tool. Omit these arguments from argumentsJson. Repeat argumentName when the connector field accepts an array of files.',
          maxItems: 10,
          items: {
            type: 'object',
            properties: {
              argumentName: { type: 'string' },
              path: { type: 'string' },
              mimeType: { type: 'string' }
            },
            required: ['argumentName', 'path', 'mimeType'],
            additionalProperties: false
          }
        }
      },
      required: [
        'action',
        'toolkit',
        'query',
        'toolSlug',
        'argumentsJson',
        'localFiles'
      ],
      additionalProperties: false
    },
    strict: true
  },
  publish_task_output: {
    type: 'function',
    name: 'publish_task_output',
    description:
      'Publish the substantial reading deliverable from a Dony To-do task as a polished private local browser output. Use once when the main result is a summary, brief, report, analysis, comparison, plan, itinerary, or similar document. Do not use for short answers, routine actions, or code changes.',
    parameters: {
      type: 'object',
      properties: {
        kind: {
          type: 'string',
          enum: [
            'summary',
            'brief',
            'report',
            'analysis',
            'comparison',
            'plan',
            'itinerary',
            'output'
          ],
          description:
            'The real deliverable type. Use output only when no specific type fits.'
        },
        title: {
          type: 'string',
          description: 'Concise reader-facing document title.'
        },
        html: {
          type: 'string',
          description:
            'Complete self-contained HTML document with inline CSS. Use semantic HTML, Dony-neutral styling, no scripts, and no external assets.'
        }
      },
      required: ['kind', 'title', 'html'],
      additionalProperties: false
    },
    strict: true
  },
  ask_user: {
    type: 'function',
    name: 'ask_user',
    description:
      'Ask the user only when a missing decision would significantly change the intended outcome, or before an irreversible, destructive, sensitive, costly, or external action. Do not ask about conventional low-risk details or steps directly implied by the request.',
    parameters: {
      type: 'object',
      properties: {
        header: {
          type: ['string', 'null'],
          description: 'Short title for the question, or null.'
        },
        question: {
          type: 'string',
          description:
            'The exact question to show the user. Include the relevant draft or proposed action when asking for confirmation.'
        },
        optionsJson: {
          type: ['string', 'null'],
          description:
            'Optional JSON array string of options with id, label, and optional description. Use null for free-form questions.'
        },
        allowCustomAnswer: {
          type: 'boolean',
          description:
            'Whether the user can type a custom answer. Use true for missing details and false for strict confirmations.'
        },
        multiple: {
          type: 'boolean',
          description:
            'Whether the user may select more than one option. Use false for free-form and single-choice questions.'
        },
        responseKind: {
          type: 'string',
          enum: ['text', 'resource'],
          description:
            'Use resource when the answer should be a file or link. Use text for decisions and ordinary free-form answers.'
        }
      },
      required: [
        'header',
        'question',
        'optionsJson',
        'allowCustomAnswer',
        'multiple',
        'responseKind'
      ],
      additionalProperties: false
    },
    strict: true
  }
};
