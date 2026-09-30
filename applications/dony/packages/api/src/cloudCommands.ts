import { randomUUID } from 'node:crypto';
import {
  companionThreadSchema,
  taskSchema,
  type CloudCommand,
  type CloudSnapshot,
  type CompanionReceipt
} from '@dony/domain';

export class CloudError extends Error {
  constructor(
    public status: 400 | 401 | 403 | 404 | 409 | 413 | 429 | 503,
    message: string
  ) {
    super(message);
  }
}

export type CloudJobDraft = {
  id: string;
  threadId: string;
  assistantMessageId: string;
  kind: 'chat' | 'plan';
  files: NonNullable<CompanionReceipt['file']>[];
};
export type CloudMutation = { job?: CloudJobDraft; stopRunId?: string };
export const cloudNow = () => new Date().toISOString();

export function createCloudThread(
  snapshot: CloudSnapshot,
  agentId: string,
  id: string,
  taskId: string | null = null
) {
  const agent = snapshot.agents.find((item) => item.id === agentId);
  if (!agent) throw new CloudError(404, 'This agent is no longer available.');
  const now = cloudNow();
  const thread = companionThreadSchema.parse({
    id,
    agentId,
    origin: taskId ? 'task' : 'direct',
    taskId,
    title: taskId
      ? snapshot.tasks.find((item) => item.id === taskId)?.title
      : agent.name,
    createdAt: now,
    updatedAt: now,
    archivedAt: null,
    viewedAt: null,
    messages: [],
    runId: null,
    status: 'ready',
    activity: null,
    instanceNumber: taskId
      ? 1 +
        snapshot.threads.filter(
          (item) => item.agentId === agentId && item.origin === 'task'
        ).length
      : null,
    question: null
  });
  snapshot.threads.push(thread);
  return thread;
}

export function queueCloudChat(
  snapshot: CloudSnapshot,
  threadId: string,
  message: string,
  messageId: string = randomUUID(),
  files: CloudJobDraft['files'] = []
): CloudJobDraft {
  const thread = snapshot.threads.find(
    (item) => item.id === threadId && !item.archivedAt
  );
  if (!thread)
    throw new CloudError(404, 'This conversation is no longer available.');
  if (thread.status === 'running' || thread.question)
    throw new CloudError(
      409,
      'Wait for this agent or answer its question first.'
    );
  const now = cloudNow();
  const id = randomUUID();
  const assistantMessageId = randomUUID();
  thread.messages.push(
    {
      id: messageId,
      threadId,
      role: 'user',
      content: message,
      status: 'complete',
      createdAt: now,
      updatedAt: now
    },
    {
      id: assistantMessageId,
      threadId,
      role: 'assistant',
      content: '',
      status: 'pending',
      createdAt: now,
      updatedAt: now
    }
  );
  thread.runId = id;
  thread.executionTarget = 'cloud';
  thread.status = 'running';
  thread.activity = 'Queued';
  thread.updatedAt = now;
  thread.viewedAt = null;
  thread.sidebarExpiresAt = null;
  if (thread.messages.length === 2 && thread.origin === 'direct')
    thread.title = message.trim().slice(0, 100) || thread.title;
  const task = snapshot.tasks.find((item) => item.id === thread.taskId);
  if (task) {
    for (const result of snapshot.results) {
      if (
        result.taskId === task.id &&
        result.outcome === 'review' &&
        !result.dismissedAt
      ) {
        result.dismissedAt = now;
        result.updatedAt = now;
      }
    }
    task.proactivePlanningStatus = null;
    task.proactiveExecutionStatus = 'queued';
    task.updatedAt = now;
  }
  return { id, threadId, assistantMessageId, kind: 'chat', files };
}

export function queueCloudTask(
  snapshot: CloudSnapshot,
  taskId: string
): CloudJobDraft {
  const task = snapshot.tasks.find(
    (item) => item.id === taskId && !item.deletedAt
  );
  if (!task || task.status === 'done')
    throw new CloudError(409, 'This task is no longer active.');
  const agentId = task.proactiveAssignedAgentId ?? snapshot.agents[0]?.id;
  if (!agentId) throw new CloudError(409, 'Create an agent first.');
  let thread = snapshot.threads.find(
    (item) => item.taskId === taskId && !item.archivedAt
  );
  thread ??= createCloudThread(snapshot, agentId, randomUUID(), taskId);
  task.proactiveAssignedAgentId = thread.agentId;
  task.proactiveSuggestionPending = false;
  return queueCloudChat(snapshot, thread.id, task.title);
}

function deleteCloudTask(snapshot: CloudSnapshot, taskId: string, now: string) {
  const ids = new Set([
    taskId,
    ...snapshot.tasks
      .filter((item) => item.parentTaskId === taskId)
      .map((item) => item.id)
  ]);
  snapshot.tasks = snapshot.tasks.filter((item) => !ids.has(item.id));
  for (const thread of snapshot.threads) {
    if (!thread.taskId || !ids.has(thread.taskId)) continue;
    thread.archivedAt = now;
    thread.updatedAt = now;
    thread.question = null;
    thread.activity = null;
    thread.status = 'ready';
  }
  snapshot.results = snapshot.results.filter((item) => !ids.has(item.taskId));
}

export function applyCloudCommand(
  snapshot: CloudSnapshot,
  command: CloudCommand
): CloudMutation {
  const action = command.action;
  const now = cloudNow();
  const task =
    'taskId' in action
      ? snapshot.tasks.find(
          (item) => item.id === action.taskId && !item.deletedAt
        )
      : undefined;
  if (
    'expectedUpdatedAt' in action &&
    (!task || task.updatedAt !== action.expectedUpdatedAt)
  ) {
    throw new CloudError(
      409,
      'This task changed on another device. Review its latest version and retry.'
    );
  }
  switch (action.type) {
    case 'task.create': {
      if (snapshot.tasks.some((item) => item.id === action.taskId))
        throw new CloudError(409, 'This task already exists.');
      const parent = action.input.parentTaskId
        ? snapshot.tasks.find((item) => item.id === action.input.parentTaskId)
        : null;
      if (action.input.parentTaskId && (!parent || parent.parentTaskId))
        throw new CloudError(
          400,
          'Choose an existing top-level task for this subtask.'
        );
      snapshot.tasks.push(
        taskSchema.parse({
          ...action.input,
          id: action.taskId,
          status: 'todo',
          parentTaskId: parent?.id ?? null,
          sortOrder: snapshot.tasks.filter(
            (item) => item.parentTaskId === (parent?.id ?? null)
          ).length,
          notes: action.input.notes ?? null,
          createdAt: now,
          updatedAt: now,
          completedAt: null,
          deletedAt: null
        })
      );
      break;
    }
    case 'task.update':
      if (
        action.patch.proactiveAssignedAgentId &&
        !snapshot.agents.some(
          (item) => item.id === action.patch.proactiveAssignedAgentId
        )
      )
        throw new CloudError(400, 'Choose an existing agent.');
      Object.assign(task!, action.patch, { updatedAt: now });
      if (action.patch.status)
        task!.completedAt = action.patch.status === 'done' ? now : null;
      if (action.patch.title !== undefined || action.patch.notes !== undefined)
        task!.proactiveEvaluationKey = null;
      break;
    case 'task.delete': {
      deleteCloudTask(snapshot, action.taskId, now);
      break;
    }
    case 'task.reorder': {
      const siblings = snapshot.tasks
        .filter((item) => item.parentTaskId === action.input.parentTaskId)
        .sort((a, b) => a.sortOrder - b.sortOrder);
      if (
        JSON.stringify(siblings.map((item) => item.id)) !==
          JSON.stringify(action.expectedOrder) ||
        siblings.length !== action.input.taskIds.length ||
        siblings.some((item) => !action.input.taskIds.includes(item.id))
      ) {
        throw new CloudError(
          409,
          'The task order changed on another device. Review it and retry.'
        );
      }
      action.input.taskIds.forEach((id, sortOrder) =>
        Object.assign(
          siblings.find((item) => item.id === id)!,
          { sortOrder, updatedAt: now }
        )
      );
      break;
    }
    case 'mode.set':
      if (snapshot.mode !== action.expectedMode)
        throw new CloudError(409, 'The agent mode changed on another device.');
      snapshot.mode = action.mode;
      break;
    case 'chat.create':
      if (snapshot.threads.some((item) => item.id === action.threadId))
        throw new CloudError(409, 'This chat already exists.');
      createCloudThread(snapshot, action.agentId, action.threadId);
      break;
    case 'chat.send': {
      if (!action.message.trim() && !action.files.length)
        throw new CloudError(400, 'Write a message or attach a file.');
      if (
        action.files.reduce(
          (total, file) => total + Buffer.byteLength(file.base64, 'base64'),
          0
        ) >
        20 * 1024 * 1024
      )
        throw new CloudError(413, 'Attachments must total 20 MB or less.');
      const job = queueCloudChat(
        snapshot,
        action.threadId,
        action.message,
        command.id,
        action.files
      );
      if (action.thinking) {
        snapshot.threads.find(
          (thread) => thread.id === action.threadId
        )!.thinking = action.thinking;
      }
      return { job };
    }
    case 'chat.archive': {
      const thread = snapshot.threads.find(
        (item) => item.id === action.threadId
      );
      if (!thread) throw new CloudError(404, 'Conversation not found.');
      thread.archivedAt = now;
      thread.updatedAt = now;
      thread.question = null;
      thread.activity = null;
      thread.status = 'ready';
      if (thread.origin === 'task' && thread.taskId)
        deleteCloudTask(snapshot, thread.taskId, now);
      return thread.runId ? { stopRunId: thread.runId } : {};
    }
    case 'chat.viewed': {
      const thread = snapshot.threads.find(
        (item) => item.id === action.threadId
      );
      if (!thread) throw new CloudError(404, 'Conversation not found.');
      thread.viewedAt ??= action.viewedAt;
      if (
        thread.origin === 'task' &&
        thread.status !== 'running' &&
        !thread.question
      )
        thread.sidebarExpiresAt = new Date(
          new Date(thread.viewedAt).getTime() + 86_400_000
        ).toISOString();
      break;
    }
    case 'run.stop': {
      const thread = snapshot.threads.find(
        (item) => item.id === action.threadId && item.runId === action.runId
      );
      if (!thread) throw new CloudError(409, 'This run is no longer active.');
      thread.status = 'ready';
      thread.activity = null;
      thread.question = null;
      const task = snapshot.tasks.find((item) => item.id === thread.taskId);
      if (task) {
        task.proactiveExecutionStatus = null;
        task.updatedAt = now;
      }
      for (const message of thread.messages)
        if (message.status === 'pending') message.status = 'complete';
      return { stopRunId: action.runId };
    }
    case 'question.answer': {
      const thread = snapshot.threads.find(
        (item) => item.question?.id === action.questionId
      );
      if (!thread?.question)
        throw new CloudError(409, 'This question was already answered.');
      const question = thread.question;
      const response = action.response;
      if (response.action !== 'accept') {
        thread.question = null;
        thread.status = 'ready';
        thread.activity = null;
        const task = snapshot.tasks.find((item) => item.id === thread.taskId);
        if (task) {
          task.proactiveExecutionStatus = null;
          task.updatedAt = now;
        }
        return thread.runId ? { stopRunId: thread.runId } : {};
      }
      if (
        response.answers.length !== question.questions.length ||
        new Set(response.answers.map((item) => item.questionId)).size !==
          response.answers.length
      )
        throw new CloudError(400, 'Answer every question once.');
      const answers = response.answers.map((answer) => {
        const item = question.questions.find(
          (item) => item.id === answer.questionId
        );
        if (!item)
          throw new CloudError(
            400,
            'This answer does not belong to the question.'
          );
        if (answer.type === 'custom') {
          if (!item.allowCustomAnswer)
            throw new CloudError(400, 'Choose one of the available answers.');
          return { question: item.question, answer: answer.customText };
        }
        const ids =
          answer.type === 'option'
            ? [answer.selectedOptionId]
            : answer.selectedOptionIds;
        if (
          (!item.multiple && ids.length !== 1) ||
          ids.some((id) => !item.options.some((option) => option.id === id))
        )
          throw new CloudError(400, 'Choose one of the available answers.');
        return {
          question: item.question,
          answer: ids
            .map((id) => item.options.find((option) => option.id === id)!.label)
            .join(', ')
        };
      });
      thread.question = null;
      thread.status = 'ready';
      const job = queueCloudChat(
        snapshot,
        thread.id,
        answers.map((item) => `${item.question}\n${item.answer}`).join('\n\n'),
        command.id,
        response.files
      );
      thread.messages.find((item) => item.id === command.id)!.questionAnswer = {
        id: question.id,
        header: question.header,
        answers
      };
      return { job };
    }
    case 'task.suggestion':
      if (action.action === 'dismiss') {
        task!.proactiveSuggestionPending = false;
        task!.updatedAt = now;
        break;
      }
      return { job: queueCloudTask(snapshot, action.taskId) };
    case 'task.review': {
      const result = snapshot.results.find(
        (item) =>
          item.id === action.resultId &&
          item.outcome === 'review' &&
          !item.dismissedAt
      );
      const reviewedTask = snapshot.tasks.find(
        (item) => item.id === result?.taskId
      );
      if (!result || !reviewedTask)
        throw new CloudError(
          409,
          'This result is no longer waiting for review.'
        );
      result.updatedAt = now;
      if (action.action === 'accept') {
        result.outcome = 'completed';
        Object.assign(reviewedTask, {
          status: 'done',
          completedAt: now,
          updatedAt: now,
          proactiveExecutionStatus: null
        });
        break;
      }
      result.dismissedAt = now;
      return {
        job: queueCloudChat(
          snapshot,
          result.threadId,
          action.feedback.trim() || 'Please revise this result.',
          command.id
        )
      };
    }
    case 'result.dismiss': {
      const result = snapshot.results.find(
        (item) => item.id === action.resultId
      );
      if (!result) throw new CloudError(404, 'Result not found.');
      result.dismissedAt = now;
      break;
    }
    case 'artifact.read':
      break;
  }
  return {};
}
