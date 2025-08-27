// Basic string sanitization to prevent code injection and SQL injection
export function sanitizeString(input: string): string {
  if (typeof input !== 'string') {
    return '';
  }
  
  return input
    .trim()
    .replace(/[<>]/g, '') // Remove < and > characters
    .replace(/javascript:/gi, '') // Remove javascript: protocol
    .replace(/on\w+\s*=/gi, '') // Remove event handlers like onclick=
    .replace(/script/gi, '') // Remove script tags
    .replace(/['";\\]/g, '') // Remove quotes and backslashes for SQL injection
    .replace(/(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|UNION|OR|AND)\b)/gi, '') // Remove SQL keywords
    .replace(/--/g, '') // Remove SQL comment syntax
    .replace(/\/\*/g, '') // Remove SQL block comment start
    .replace(/\*\//g, '') // Remove SQL block comment end
    .substring(0, 1000); // Limit length to 1000 characters
}

export function sanitizeFormData(formData: FormData): { [key: string]: string } {
  const sanitized: { [key: string]: string } = {};
  
  for (const [key, value] of formData.entries()) {
    if (typeof value === 'string') {
      sanitized[key] = sanitizeString(value);
    } else {
      // If value is a File, you may want to handle it differently or skip
      sanitized[key] = '';
    }
  }
  
  return sanitized;
}