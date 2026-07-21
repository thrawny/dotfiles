import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const MAX_MATCHES = 3;
const MAX_OUTPUT_CHARS = 8_000;

export default function historyQueryExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "history_query",
		label: "History query",
		description:
			"Retrieve bounded matching turns from one local Pi, Codex, or Claude session. Use only when a specific missing fact blocks the current task; do not use it to reconstruct or broadly reread prior context. The session defaults to this session's parent.",
		parameters: Type.Object({
			query: Type.String({
				description: "A narrow search phrase for the missing fact.",
				minLength: 1,
			}),
			session: Type.Optional(
				Type.String({
					description:
						"Session id or path. Omit to query the current session's parent.",
				}),
			),
			limit: Type.Optional(
				Type.Integer({
					description: "Number of non-overlapping matches, from 1 to 3.",
					minimum: 1,
					maximum: MAX_MATCHES,
				}),
			),
			includeTools: Type.Optional(
				Type.Boolean({
					description:
						"Include tool calls/results. Keep false unless the missing fact is specifically in tool output.",
				}),
			),
		}),
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const query = params.query.trim();
			if (!query) {
				return {
					content: [
						{
							type: "text" as const,
							text: "Provide a non-empty narrow query.",
						},
					],
					details: { error: true },
					isError: true,
				};
			}
			const session =
				params.session?.trim() || ctx.sessionManager.getHeader()?.parentSession;
			if (!session) {
				return {
					content: [
						{
							type: "text" as const,
							text: "No parent session is recorded; provide a session id or path.",
						},
					],
					details: { error: true },
					isError: true,
				};
			}

			const limit = Math.max(
				1,
				Math.min(params.limit ?? MAX_MATCHES, MAX_MATCHES),
			);
			const args = [
				"query",
				session,
				query,
				"--limit",
				String(limit),
				"--max-chars",
				String(MAX_OUTPUT_CHARS),
			];
			if (params.includeTools) args.push("--include-tools");

			const result = await pi.exec("agent-history", args, {
				cwd: ctx.cwd,
				signal,
				timeout: 15_000,
			});
			if (result.code !== 0) {
				const message =
					result.stderr.trim() ||
					result.stdout.trim() ||
					`agent-history exited with code ${result.code}`;
				return {
					content: [{ type: "text" as const, text: message }],
					details: { error: true, session },
					isError: true,
				};
			}
			return {
				content: [
					{
						type: "text" as const,
						text:
							result.stdout.trim() || "No matching history entries were found.",
					},
				],
				details: { session, query, limit },
			};
		},
	});
}
