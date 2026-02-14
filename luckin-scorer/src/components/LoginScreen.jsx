import React, { useState } from 'react';

export default function LoginScreen({ onLogin, error }) {
  const [password, setPassword] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    onLogin(password);
  };

  return (
    <div className="min-h-screen bg-bg flex items-center justify-center px-4">
      <div className="bg-card border border-border rounded-card shadow-sm p-8 w-full max-w-sm">
        <div className="text-center mb-6">
          <div className="text-4xl mb-3">☕</div>
          <h1 className="text-2xl font-bold text-text-primary">瑞幸咖啡</h1>
          <p className="text-sm text-text-secondary mt-1">选址评估系统</p>
          <p className="text-xs text-text-muted mt-0.5">Site Selection Tool</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-text-secondary mb-1">
              密码 Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent-teal/30 focus:border-accent-teal"
              placeholder="请输入密码"
              autoFocus
            />
          </div>

          {error && (
            <p className="text-sm text-accent-red">{error}</p>
          )}

          <button
            type="submit"
            className="w-full py-2.5 bg-accent-teal text-white rounded-lg text-sm font-medium hover:bg-accent-teal/90 transition-colors"
          >
            登录 Login
          </button>
        </form>

        <p className="text-xs text-text-muted text-center mt-6">
          Luckin Coffee USA — Internal Tool
        </p>
      </div>
    </div>
  );
}
