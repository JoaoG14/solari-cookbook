import { z } from 'zod';

export const trimmedStringSchema = z.string().trim();
export const nonEmptyTrimmedStringSchema = trimmedStringSchema.min(1);
export const nullableTrimmedStringSchema = z.string().trim().nullable();
