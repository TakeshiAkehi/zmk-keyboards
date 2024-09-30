github_user=`git config user.name`
echo "github user = $github_user"

SCRIPT_DIR=$(cd $(dirname $0); pwd)
cd $SCRIPT_DIR

if [ $# -ne 1 ]; then
  echo "repo name?"
  exit 1
fi

repo_name="$1"
repo_path="https://github.com/zmkfirmware/unified-zmk-config-template.git"
github_repo="https://github.com/${github_user}/${repo_name}.git"

cd keyboards
git clone --single-branch $repo_path ${repo_name}
cd $repo_name
rm -rf .git
git init .
git add .
git commit -m "initial commit"
git remote add origin "$github_repo"
git push --set-upstream origin "$(git symbolic-ref --short HEAD)"


push_return_code=$?

# If push failed, assume that the origin was incorrect and give instructions on fixing.
if [ ${push_return_code} -ne 0 ]; then
    echo "Remote repository $github_repo not found..."
    echo "Check GitHub URL, and try adding again."
    echo "Run the following: "
    echo "    git remote rm origin"
    echo "    git remote add origin FIXED_URL"
    echo "    git push --set-upstream origin $(git symbolic-ref --short HEAD)"
    echo "Once pushed, your firmware should be available from GitHub Actions at: ${github_repo%.git}/actions"
fi

cd ..
git submodule add $github_repo $repo_name
