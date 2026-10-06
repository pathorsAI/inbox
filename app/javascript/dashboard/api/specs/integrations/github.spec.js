import GithubAPIClient from '../../integrations/github';
import ApiClient from '../../ApiClient';

describe('#githubAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
  });

  afterEach(() => {
    window.axios = originalAxios;
    vi.clearAllMocks();
  });

  it('creates correct instance', () => {
    expect(GithubAPIClient).toBeInstanceOf(ApiClient);
  });

  it('completes an installation', () => {
    GithubAPIClient.connect({
      code: 'oauth-code',
      installationId: '81234567',
      state: 'signed-state',
    });
    expect(axiosMock.post).toHaveBeenCalledWith('/api/v1/integrations/github', {
      code: 'oauth-code',
      installation_id: '81234567',
      state: 'signed-state',
    });
  });

  it('fetches the repositories of the installation', () => {
    GithubAPIClient.getRepositories();
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/integrations/github/repositories'
    );
  });

  it('saves the repository and label', () => {
    GithubAPIClient.updateSettings({
      repository: 'pathorsAI/inbox',
      label: 'support',
    });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/integrations/github',
      { repository: 'pathorsAI/inbox', label: 'support' }
    );
  });

  it('sends an empty label to clear it', () => {
    GithubAPIClient.updateSettings({
      repository: 'pathorsAI/inbox',
      label: '',
    });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/integrations/github',
      { repository: 'pathorsAI/inbox', label: '' }
    );
  });
});
