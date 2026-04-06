export function getStatusRedirect(
  type: "error" | "success",
  path: string,
  message: string,
) {
  const params = new URLSearchParams({ [type]: message });
  return `${path}?${params.toString()}`;
}
