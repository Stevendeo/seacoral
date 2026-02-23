int sum(int* p, int n) {
  int res = 0;
  for (int i = 0; i < n; i++){
    res += p[i];
  }
  return res;
}

int mult(int* q, int m) {
  int res = 1;
  for (int i = 0; i < m; i++){
    res *= q[i];
  }
  return res;
}
